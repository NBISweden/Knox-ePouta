#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings/common.sh
source $(dirname ${BASH_SOURCE[0]})/settings/boot.sh

# Default values
_CLOUD=''
_IMAGE=CentOS7

declare -A MACHINE_FLAVORS
MACHINE_FLAVORS=(\
    [supernode]=m1.small \
    [knox1]=m1.large \
    [knox2]=m1.large \
    [knox3]=m1.large \
    [storage]=mm.storage \
)

KE_PORT=12345

function usage {
    echo "Usage: ${KE_CMD:-$0} [options]"
    echo -e "\noptions are"
    echo -e "\t--cloud <credentials> \tChoose which cloud to boot on"
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

[ -z "$_CLOUD" ] && echo "ERROR: You must specify the --cloud"
if [ -f $KE_HOME/settings/${_CLOUD}.rc ]; then
    source $KE_HOME/settings/${_CLOUD}.rc
else
    echo "ERROR: Cloud credentials not found [$KE_HOME/settings/${_CLOUD}.rc]"
    exit 1;
fi

if [ -z $OS_TENANT_NAME ]; then
    echo "ERROR: No tenant name found in [$KE_HOME/settings/${_CLOUD}.rc]"
    echo "Exiting..."
    exit 1;
fi
export OS_PROJECT_NAME=${OS_TENANT_NAME}

if [ -z "$TENANT_ID" ]; then
    echo "ERROR: Tenant ID not specified (for tenant ${OS_TENANT_NAME})"
    exit 1
fi

# Checking if the user is admin for that tenant
CHECK=$(openstack role assignment list --user ${OS_USERNAME} --role admin --project ${OS_TENANT_NAME})
if [ $? -ne 0 ] || [ -z "$CHECK" ]; then
    echo "ERROR: $CHECK"
    echo -e "\nThe user ${OS_USERNAME} does not seem to have the 'admin' role for the project ${OS_TENANT_NAME}"
    echo "Exiting..."
    exit 1
fi

#######################################################################
# Create the host file first
cat > ${KE_TMP}/hosts <<ENDHOST
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

130.238.7.178 uu_proxy
ENDHOST
for name in ${!MACHINES_IPs[@]}; do echo "${MACHINE_IPs[$name]} $name" >> ${KE_TMP}/hosts; done

#######################################################################
# Logic to allow the user to specify some machines
# Otherwise, continue with the ones in settings.sh
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

# # Removing the Epouta machines
# for machine in ${MACHINES[@]}; do [[ $machine == 'epouta'* ]] && unset unset MACHINES[$machine]; done

#######################################################################
# Testing if the image exists
if nova image-list | grep "${_IMAGE}" > /dev/null; then : ; else
    echo "Error: Could not find the image '${_IMAGE}' to boot from."
    exit 1
fi

MGMT_NET=$(neutron net-list --tenant_id=${TENANT_ID} | awk "/ ${OS_TENANT_NAME}-mgmt-net /{print \$2}")
if [ -z "$MGMT_NET" ]; then
    echo "Error: Could not find the Management"
    exit 1
fi

#######################################################################
# Checking the network namespace 
if [ ! -r ${KE_TMP}/netns ]; then
     echo "Error: Virtual router not found"
     exit 1
fi
NETNS=$(<${KE_TMP}/netns) # bash only
KE_CONNECT="sudo -E ip netns exec $NETNS"

#######################################################################
[ $VERBOSE == 'no' ] && exec 1>${KE_TMP}/init.log
ORG_FD1=$(tty)

#######################################################################
# Prepare the tmp folders
for machine in ${MACHINES[@]}; do mkdir -p ${KE_TMP}/$machine/init; done

########################################################################
# Start the local REST server, to follow the progress of the machines
########################################################################
echo "Starting the REST phone home server"
$KE_CONNECT fuser -k ${KE_PORT}/tcp || true
trap "$KE_CONNECT fuser -k ${KE_PORT}/tcp &>/dev/null || true; exit 1" SIGINT SIGTERM EXIT
$KE_CONNECT python ${KE_HOME}/lib/init-progress.py $KE_PORT "${MACHINES[@]}" 2>&1 &
REST_PID=$!
sleep 2

function boot_machine {
    local machine=$1
    local ip=${MACHINE_IPs[$machine]}
    local flavor=${MACHINE_FLAVORS[$machine]}

    _VM_INIT=${KE_TMP}/$machine/init/vm.sh
    echo '#!/usr/bin/env bash' > ${_VM_INIT}
    for user in ${!PUBLIC_SSH_KEYS[@]}; do echo "echo '${PUBLIC_SSH_KEYS[$user]}' >> /home/centos/.ssh/authorized_keys" >> ${_VM_INIT}; done
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
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
ENDCLOUDINIT
    cat ${KE_TMP}/hosts >> ${_VM_INIT}
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
EOF
chown root:root /etc/hosts
chmod 0644 /etc/hosts
ENDCLOUDINIT

    # sed -i 's/^Defaults.*requiretty/#&/g' /etc/sudoers
    # Final part: Grow partition and phone home
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
echo "================================================================================"
echo "Growing partition to disk size"
curl http://${MGMT_GATEWAY}:$KE_PORT/machine/$machine/growing 2>&1 > /dev/null || true
growpart /dev/vda 1
echo "================================================================================"
echo "Cloudinit phone home"
curl http://${MGMT_GATEWAY}:$KE_PORT/machine/$machine/ready 2>&1 > /dev/null || true
ENDCLOUDINIT

# Booting a machine
echo -e "\t* $machine"
nova boot --flavor $flavor --image ${_IMAGE} --security-groups default,${OS_TENANT_NAME}-sg \
--nic net-id=${MGMT_NET},v4-fixed-ip=$ip --user-data ${_VM_INIT} \
$machine &>/dev/null

} # End boot_machine function

# # On Epouta
# nova boot --flavor hpc.small --image "CentOS7-extended" --security-groups default \
# --nic net-id=af8c6b4c-55b8-41de-a1ec-943e9a06d1e7 epouta-name


########################################################################
# Aaaaannndddd....cue music!
########################################################################
echo "Booting the machines"
for machine in ${MACHINES[@]}; do boot_machine $machine; done

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

echo -e "\nInitialization phase complete."
