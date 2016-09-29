#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings.sh

# Default values
EPOUTA_NODES=3
_IMAGE=CentOS7-extended

function usage {
    echo "Usage: ${MM_CMD:-$0} [options]"
    echo -e "\noptions are"
    echo -e "\t--image <img>,"
    echo -e "\t     -i <img>    \tGlance image to use. Defaults to ${_IMAGE}"
    echo -e "\t--nodes,-n <int> \tNumber of Epouta nodes to boot. Defaults to ${EPOUTA_NODES}"
    echo -e "\t--quiet,-q       \tRemoves the verbose output"
    echo -e "\t--help,-h        \tOutputs this message and exits"
    echo -e "\t-- ...           \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) VERBOSE=no;;
        --image|-i) _IMAGE=$2; shift;;
        --nodes|-n) EPOUTA_NODES=$2; shift;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

mkdir -p ${MM_TMP}

[ $VERBOSE == 'no' ] && exec 1>${MM_TMP}/init-epouta.log
ORG_FD1=$(tty)

# Create the host file first
cat > ${MM_TMP}/hosts <<ENDHOST
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

130.238.7.178 uu_proxy
ENDHOST
for name in ${MACHINES[@]}; do echo "${MACHINE_IPs[$name]} $name" >> ${MM_TMP}/hosts; done

#######################################################################
# RESET for Epouta
#######################################################################
MACHINES=('leif')
MACHINE_IPs[leif]=${MGMT_CIDR%.0.0/16}.0.10
for i in $(eval echo {1..${EPOUTA_NODES}}); do
    MACHINES+=(epouta-$i)
    MACHINE_IPs[epouta-$i]=${MGMT_CIDR%.0.0/16}.0.$(( 20 + i ))
done

#######################################################################
# Adding epouta nodes to /etc/hosts
for name in ${MACHINES[@]}; do echo "${MACHINE_IPs[$name]} $name" >> ${MM_TMP}/hosts; done

#######################################################################
# Prepare the tmp folders
for machine in ${MACHINES[@]}; do mkdir -p ${MM_TMP}/$machine/init; done

#######################################################################
# Credentials for Epouta. Should reset the ones from settings.sh
NETNS=$(<${MM_TMP}/netns) # bash only
[ -z $NETNS ] && echo "Unknown virtual router: mgmt-router" && exit 1

source $(dirname ${BASH_SOURCE[0]})/epouta-credentials.sh

#######################################################################
# Testing if the image exists
if nova image-list | grep "${_IMAGE}" > /dev/null; then : ; else
    echo "Error: Could not find the image '${_IMAGE}' to boot from."
    echo "Exiting..."
    exit 1
fi

EPOUTA_NET=$(neutron net-list | awk '/ UU-MOSLER-network / {print $2}')
if [ -z "$EPOUTA_NET" ]; then
    echo "Error: Could not find the epouta net... Exiting." > ${ORG_FD1}
    exit 1
fi

# Create the port
for machine in ${MACHINES[@]}; do
    if ! neutron port-show port-$machine >/dev/null; then
	neutron port-create --name port-$machine --fixed-ip subnet_id=UU-MOSLER-subnet,ip_address=${MACHINE_IPs[$machine]} UU-MOSLER-network
    fi
done

########################################################################
# Start the local REST server, to follow the progress of the machines
#######################################################################
echo "Starting the REST phone home server"
sudo -E ip netns exec $NETNS fuser -k ${PORT}/tcp || true
trap "sudo -E ip netns exec $NETNS fuser -k ${PORT}/tcp &>/dev/null || true; exit 1" SIGINT SIGTERM EXIT
sudo -E ip netns exec $NETNS python ${MM_HOME}/lib/boot_progress.py $PORT "${MACHINES[@]}" 2>&1 &
REST_PID=$!
sleep 2

#######################################################################
function boot_machine {
    local machine=$1
    local ip=${MACHINE_IPs[$machine]}

    local _port=$(neutron port-list 2>/dev/null | awk "/ port-$machine / {print \$2}")
    [ -z "$_port" ] && echo "Could not find the neutron port for $machine. Skipping..." && return 1

    _VM_INIT=${MM_TMP}/$machine/init/vm.sh
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
echo "Adding the routing tables"
echo '10 mgmt' >> /etc/iproute2/rt_tables
echo '12 ext' >> /etc/iproute2/rt_tables
echo "================================================================================"
echo "Creating hosts file"
cat > /etc/hosts <<EOF
ENDCLOUDINIT
    cat ${MM_TMP}/hosts >> ${_VM_INIT}
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
EOF
chown root:root /etc/hosts
chmod 0644 /etc/hosts
ENDCLOUDINIT

    # Final part: Grow partition and phone home
    # sed -i 's/^Defaults.*requiretty/#&/g' /etc/sudoers
    cat >> ${_VM_INIT} <<ENDCLOUDINIT
echo "================================================================================"
echo "Growing partition to disk size"
curl http://${MGMT_GATEWAY}:$PORT/machine/$machine/growing 2>&1 > /dev/null || true
growpart /dev/vda 1
echo "================================================================================"
echo "Cloudinit phone home"
curl http://${MGMT_GATEWAY}:$PORT/machine/$machine/ready 2>&1 > /dev/null || true
ENDCLOUDINIT

# Booting a machine
echo -e "\t* $machine"
# nova boot --flavor hpc.small --image ${_IMAGE} \
# --nic net-id=${EPOUTA_NET},v4-fixed-ip=$ip --user-data ${_VM_INIT} \
# $machine &>/dev/null


nova boot --flavor hpc.small --image ${_IMAGE} \
--nic port-id=$_port --user-data ${_VM_INIT} \
$machine #&>/dev/null
##--nic net-id=${EPOUTA_NET} --user-data ${_VM_INIT} \

} # End boot_machine function


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


