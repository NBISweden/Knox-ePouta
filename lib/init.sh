#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings.sh

# Default values
_NET=no
_IMAGE=CentOS7

function usage {
    echo "Usage: ${MM_CMD:-$0} [options]"
    echo -e "\noptions are"
    echo -e "\t--net            \tCreates also networks, routers, security groups,..."
    echo -e "\t--machines <list>,"
    echo -e "\t        -m <list>\tA comma-separated list of machines"
    echo -e "\t                 \tDefaults to: \"${MACHINES[@]// /,}\"."
    echo -e "\t                 \tWe filter out machines that don't appear in the default list."
    echo -e "\t--image <img>,"
    echo -e "\t     -i <img>    \tGlance image to use. Defaults to ${_IMAGE}"
    echo -e "\t--quiet,-q       \tRemoves the verbose output"
    echo -e "\t--help,-h        \tOutputs this message and exits"
    echo -e "\t-- ...           \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --net) _NET=yes;;
        --quiet|-q) VERBOSE=no;;
        --machines|-m) CUSTOM_MACHINES=$2; shift;;
        --image|-i) _IMAGE=$2; shift;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

mkdir -p ${MM_TMP}

[ $VERBOSE == 'no' ] && exec 1>${MM_TMP}/init.log
ORG_FD1=$(tty)

# Create the host file first
cat > ${MM_TMP}/hosts <<ENDHOST
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

130.238.7.178 uu_proxy
ENDHOST
for name in ${MACHINES[@]}; do echo "${MACHINE_IPs[$name]} $name" >> ${MM_TMP}/hosts; done

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
	    echo "Unknown machine: $cm" > ${ORG_FD1}
	fi
    done
    if [ -n "$CUSTOM_MACHINES" ]; then
	echo "Using these machines: ${CUSTOM_MACHINES// /,}"
	MACHINES=($CUSTOM_MACHINES)
    else
	echo "Error: all custom machines are unknown" > ${ORG_FD1}
	echo "Nothing to be done..." > ${ORG_FD1}
	echo -e 'Exiting!' > ${ORG_FD1}
	exit 2
    fi  
fi

#######################################################################
# Prepare the tmp folders
for machine in ${MACHINES[@]}; do mkdir -p ${MM_TMP}/$machine/init; done

#######################################################################

TENANT_ID=$(openstack project list | awk "/${OS_TENANT_NAME}/ {print \$2}")
if [ -z "$TENANT_ID" ]; then
    echo "ERROR: Does tenant ${OS_TENANT_NAME} exit?" > ${ORG_FD1}
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

if [ ${_NET} = "yes" ]; then

    echo "Creating routers and networks"

    MGMT_ROUTER_ID=$(neutron router-create ${OS_TENANT_NAME}-mgmt-router | awk '/ id / { print $4 }')
    echo qrouter-$MGMT_ROUTER_ID > ${MM_TMP}/netns

    # if [ -z "$MGMT_ROUTER_ID" ]; then
    # 	echo "Router issues. Exiting..."
    #   exit 1
    # fi

    # Creating the management and data networks
    neutron net-create --provider:network_type vlan --provider:physical_network vlan --provider:segmentation_id ${MM_VLAN} ${OS_TENANT_NAME}-mgmt-net >/dev/null
    neutron subnet-create --name ${OS_TENANT_NAME}-mgmt-subnet ${OS_TENANT_NAME}-mgmt-net --allocation-pool start=${MGMT_ALLOCATION_START},end=${MGMT_ALLOCATION_END} --gateway ${MGMT_GATEWAY} ${MGMT_CIDR} >/dev/null # --disable-dhcp
    neutron router-interface-add ${OS_TENANT_NAME}-mgmt-router ${OS_TENANT_NAME}-mgmt-subnet >/dev/null

    echo "Creating the Security Group: ${OS_TENANT_NAME}-sg"
    nova secgroup-create ${OS_TENANT_NAME}-sg "Security Group for ${OS_TENANT_NAME}" >/dev/null
    #nova secgroup-add-rule ${OS_TENANT_NAME}-sg icmp  -1    -1 ${FLOATING_CIDR}      >/dev/null
    nova secgroup-add-rule ${OS_TENANT_NAME}-sg icmp  -1    -1 ${MGMT_CIDR}          >/dev/null
    #nova secgroup-add-rule ${OS_TENANT_NAME}-sg tcp   22    22 ${FLOATING_CIDR}      >/dev/null
    nova secgroup-add-rule ${OS_TENANT_NAME}-sg tcp    1 65535 ${MGMT_CIDR}          >/dev/null
    
    echo "Setting the quotas"
    FACTOR=2
    nova quota-update --instances $((10 * FACTOR)) --ram $((51200 * FACTOR)) ${TENANT_ID} >/dev/null

fi # End _NET config


# Testing if the image exists
if nova image-list | grep "${_IMAGE}" > /dev/null; then : ; else
    echo "Error: Could not find the image '${_IMAGE}' to boot from."
    echo "Exiting..."
    exit 1
fi

MGMT_NET=$(neutron net-list --tenant_id=${TENANT_ID} | awk "/ ${OS_TENANT_NAME}-mgmt-net /{print \$2}")

# echo "Management Net: $MGMT_NET"
echo "Checking network information"

if [ -z "$MGMT_NET" ]; then
    echo "Error: Could not find the Management" > ${ORG_FD1}
    echo -e "\tMaybe you should re-run with the --net flags?" > ${ORG_FD1}
    exit 1
fi

NETNS=$(<${MM_TMP}/netns) # bash only
[ -z $NETNS ] && echo "Unknown virtual router: ${OS_TENANT_NAME}-mgmt-router" && exit 1

########################################################################
# Start the local REST server, to follow the progress of the machines
########################################################################
echo "Starting the REST phone home server"
sudo -E ip netns exec $NETNS fuser -k ${PORT}/tcp || true
trap "sudo -E ip netns exec $NETNS fuser -k ${PORT}/tcp &>/dev/null || true; exit 1" SIGINT SIGTERM EXIT
sudo -E ip netns exec $NETNS python ${MM_HOME}/lib/boot_progress.py $PORT "${MACHINES[@]}" 2>&1 &
REST_PID=$!
sleep 2

function boot_machine {
    local machine=$1
    local ip=${MACHINE_IPs[$machine]}
    local flavor=${FLAVORS[$machine]}

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
