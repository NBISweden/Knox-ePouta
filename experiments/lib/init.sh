#!/usr/bin/env bash

# Get the general settings
source $(dirname ${BASH_SOURCE[0]})/settings/common.rc

# Default values
_IMAGE=CentOS7-extended
_CLOUD=''

function usage {
    echo "Usage: ${KE_CMD:-$0} [options]"
    echo -e "\noptions are"
    echo -e "\t--cloud <cloud>       \tWhich cloud to boot VMs on?"
    echo -e "\t--machines <list>,"
    echo -e "\t        -m <list>     \tA comma-separated list of machines"
    echo -e "\t                      \tDefaults to: \"${KNOX_MACHINES[@]// /,}\"."
    echo -e "\t                      \tWe filter out machines that don't appear in the default list."
    echo -e "\t--image <img>,"
    echo -e "\t     -i <img>         \tGlance image to use. Defaults to ${_IMAGE}"
    echo -e "\t--quiet,-q            \tRemoves the verbose output"
    echo -e "\t--help,-h             \tOutputs this message and exits"
    echo -e "\t-- ...                \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --cloud) _CLOUD=$2; shift;;
        --quiet|-q) VERBOSE=no;;
        --machines|-m) CUSTOM_MACHINES=$2; shift;;
        --image|-i) _IMAGE=$2; shift;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

#######################################################################
# Fetching the cloud settings
[ -z "$_CLOUD" ] && echo "ERROR: Which cloud do you consider?" && usage && exit 1

if [ -f $KE_HOME/lib/settings/${_CLOUD}.init ]; then
    # Adding the knox variables to the environment
    source $KE_HOME/lib/settings/${_CLOUD}.init
    # Note: this includes some rudimentary checks
    # And the definition of the boot_machine function
else
    echo "ERROR: Cloud settings not found [$KE_HOME/lib/settings/${_CLOUD}.init]"
    exit 1;
fi

#######################################################################
[ $VERBOSE == 'no' ] && exec 1>${KE_TMP}/init.log
ORG_FD1=$(tty)

# Resetting the machines afterwards
# if _CLOUD is 'knox' the next line evaluates to ${KNOX_MACHINES[@]}
# So that MACHINES is either the KNOX_MACHINES array
MACHINES=($(eval echo "\${${_CLOUD^^}_MACHINES[@]}"))

#######################################################################
# Logic to allow the user to specify some machines
if [ -n ${CUSTOM_MACHINES:-''} ]; then
    CUSTOM_MACHINES_TMP=${CUSTOM_MACHINES//,/ } # replace all commas with space
    CUSTOM_MACHINES="" # Filtering the ones which don't exist in settings.sh
    for cm in $CUSTOM_MACHINES_TMP; do
	if [[ "${MACHINES[@]}" =~ "$cm" ]]; then
	    CUSTOM_MACHINES+="$cm "
	else
	    echo "Unknown machine: $cm"
	fi
    done
    if [ -n "$CUSTOM_MACHINES" ]; then
	echo "Using these machines: ${CUSTOM_MACHINES// /,}"
	MACHINES=($CUSTOM_MACHINES)
    else
	echo "Error: all custom machines are unknown"
	echo "Nothing to be done..."
	exit 2
    fi  
fi

#######################################################################
# Testing if the image exists
# Silencing the SSL warnings from ePouta with 2>/dev/null
if nova image-list 2>/dev/null | grep "${_IMAGE}" > /dev/null; then : ; else
    echo "Error: Could not find the image '${_IMAGE}' to boot from."
    exit 1
fi

#######################################################################
# Prepare the tmp folders
for machine in ${MACHINES[@]}; do mkdir -p ${KE_TMP}/$machine/init; done

########################################################################
# Start the local REST server, to follow the progress of the machines
# Note: this script should be executed in the NETNS of the virtual router.
# The custom code to do that has been removed. (ie: no 'ip netns exec qrouter-...')
########################################################################
echo "Starting the REST phone home server"
fuser -k ${_PORT}/tcp || true
trap "$KE_CONNECT fuser -k ${_PORT}/tcp &>/dev/null || true; exit 1" SIGINT SIGTERM EXIT
python ${KE_HOME}/lib/init-progress.py $_PORT "${MACHINES[@]}" 2>&1 &
REST_PID=$!
sleep 2

function prepare_machine {
    local machine=$1

    local _VM_INIT=${KE_TMP}/$machine/init/vm.sh
    echo '#!/usr/bin/env bash' > ${_VM_INIT}
    echo "cat >> /home/centos/.ssh/authorized_keys <<EOF" >> ${_VM_INIT}
    cat ${KE_HOME}/lib/settings/authorized_keys >> ${_VM_INIT}
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
EOF
echo "================================================================================"
echo "Adjusting the timezone"
echo 'Europe/Stockholm' > /etc/timezone
echo "================================================================================"
echo "Making sudo not require TTY for the centos user"
echo 'Defaults:centos !requiretty' > /etc/sudoers.d/centos
echo 'Defaults:root !requiretty' >> /etc/sudoers.d/centos
echo "================================================================================"
echo "Making sshd not use reverse DNS lookups"
sed -i -r 's/#?UseDNS.*/UseDNS no/' /etc/ssh/sshd_config
echo "================================================================================"
echo "Disabling SElinux"
[ -f /etc/sysconfig/selinux ] && sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
[ -f /etc/selinux/config ] && sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
echo "================================================================================"
echo "Creating hosts file"
cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

130.238.7.178 uu_proxy
ENDCLOUDINIT
for name in ${!MACHINE_IPs[@]}; do echo "${MACHINE_IPs[$name]} $name" >> ${_VM_INIT}; done
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
EOF
chown root:root /etc/hosts
chmod 0644 /etc/hosts
echo "================================================================================"
echo "Growing partition to disk size"
curl http://${MGMT_GATEWAY}:${_PORT}/machine/$machine/growing 2>&1 > /dev/null || true
growpart /dev/vda 1
echo "================================================================================"
echo "Cloudinit phone home"
curl http://${MGMT_GATEWAY}:${_PORT}/machine/$machine/ready 2>&1 > /dev/null || true
ENDCLOUDINIT

} # End prepare_machine

echo "Preparing the init scripts"
for machine in ${MACHINES[@]}; do echo -e "\t* $machine"; prepare_machine $machine; done

########################################################################
# Is the boot_machine function defined
type ke_boot_machine &>/dev/null || { echo "boot function not found"; exit 1; }

# Aaaaannndddd....cue music!
echo "Booting the machines"
for machine in ${MACHINES[@]}; do
    ke_boot_machine $machine ${MACHINE_IPs[$machine]} ${_IMAGE} ${KE_TMP}/$machine/init/vm.sh
done

########################################################################
echo "Waiting for the REST phone home server"
#echo "(PID: ${REST_PID})"
wait ${REST_PID}
echo "The last machine just phoned home."

########################################################################
exec 1>${ORG_FD1}

########################################################################
trap "echo -e \"\nOr you can Ctrl-C, yes, that works too...\n\"; exit 0" SIGINT INT
REBOOT=y
ASK_TIMEOUT=10 #seconds
while : ; do # while = In a subshell
    echo -n -e "\nWould you like to reboot the servers before you provision them? [y/N] "
    read -t ${ASK_TIMEOUT} yn
    [ $? != 0 ] && echo " $REBOOT (timeout)" && break;
    case $yn in
        y) REBOOT=y; break;;
        N) REBOOT=N; break;;
        * ) echo "Eh?";;
    esac
done

[ $REBOOT = y ] && echo -n "Rebooting " && for machine in ${MACHINES[@]}; do
	echo -n "." # progress
	nova reboot $machine >/dev/null
    done

echo -e "\nInitialization phase complete for the VMs on ${_CLOUD^^}."
