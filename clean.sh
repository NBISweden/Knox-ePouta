#!/usr/bin/env bash

# Get credentials and machines settings
source ./settings.sh

# Default values
ALL=no
VERBOSE=yes

function usage(){
    echo "Usage: $0 [options]"
    echo -e "\noptions are"
    echo -e "\t--all,-a         \tDeletes also networks, routers, security groups and floating IPs"
    echo -e "\t--quiet,-q       \tRemoves the verbose output"
    echo -e "\t--help,-h        \tOutputs this message and exits"
    echo -e "\t-- ...           \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --all|-a) ALL=yes;;
        --quiet|-q) VERBOSE=no;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done                                                                                              


#######################################################################

[ $VERBOSE = "yes" ] && echo "Removing the Cloudinit folder"
rm -rf $CLOUDINIT_FOLDER

# Cleaning all the running machines
function delete_machine {
    local machine=$1
    [ $VERBOSE = "yes" ] && echo "Deleting VM: $machine"
    nova delete $machine
}

echo "Cleaning running machines"
#for machine in "${MACHINES[@]}"; do delete_machine $machine; done
nova list --minimal --tenant ${TENANT_ID} | awk '{print $4}' | while read machine; do
    # If I find the server in the MACHINES list. Otherwise, don't touch! Might not be your server
    for m in "${MACHINES[@]}"; do
	[ "$m" = "$machine" ] && delete_machine $m;
    done
done

# Cleaning the network information
if [ $ALL = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Cleaning the remaining VMs"
    nova list --minimal --tenant ${TENANT_ID} | awk '/^$/ {next;} /^| ID / {next;} /^+--/ {next;} {print $2}' | while read m; do delete_machine $m; done

    [ $VERBOSE = "yes" ] && echo "Cleaning the network information"

    [ $VERBOSE = "yes" ] && echo "Disconnecting the router from the management subnet"
    neutron router-interface-delete ${OS_TENANT_NAME}-mgmt-router ${OS_TENANT_NAME}-mgmt-subnet
    neutron router-interface-delete ${OS_TENANT_NAME}-data-router ${OS_TENANT_NAME}-data-subnet

    [ $VERBOSE = "yes" ] && echo "Deleting router"
    neutron router-delete ${OS_TENANT_NAME}-mgmt-router
    neutron router-delete ${OS_TENANT_NAME}-data-router

    [ $VERBOSE = "yes" ] && echo "Deleting networks and subnets"
    neutron subnet-delete ${OS_TENANT_NAME}-mgmt-subnet
    neutron subnet-delete ${OS_TENANT_NAME}-data-subnet
    neutron net-delete ${OS_TENANT_NAME}-mgmt-net
    neutron net-delete ${OS_TENANT_NAME}-data-net

    [ $VERBOSE = "yes" ] && echo "Deleting floating IPs"
    neutron floatingip-list -F id -F floating_ip_address | awk '/^$/ {next;} {print $2$3$4}' | while read floating; do
	# We selected '--all'. That means, we do delete the network information.
	# In that case, kill _all_ floating IPs since we also delete the networks
	neutron floatingip-delete ${floating%|*} && ssh-keygen -R ${floating%|*}
    done

    # Removing the ssh config file
    [ -f ${SSH_CONFIG} ] && rm -f ${SSH_CONFIG}

    # Cleaning the security group
    [ $VERBOSE = "yes" ] && echo "Cleaning security group: ${OS_TENANT_NAME}-sg"
    neutron security-group-delete ${OS_TENANT_NAME}-sg

fi # End cleaning if ALL

[ $VERBOSE = "yes" ] && echo "Cleaning cloudinit folder and ansible generated files"
rm -rf ${CLOUDINIT_FOLDER}
rm -f ${ANSIBLE_CONFIG} ${INVENTORY}
rm -rf ${ANSIBLE_LOGS}
unset ANSIBLE_CONFIG

[ $VERBOSE = "yes" ] && echo "Cleaning the SSH keys"
if [ -f ~/.ssh/known_hosts ]; then
    # Cut the matching keys out
    # for name in "${MACHINES[@]}"; do sed -i "/${FLOATING_IPs[$name]}/d" ~/.ssh/known_hosts; done
    sed -n -i "/${FLOATING_CIDR%0/24}/d" ~/.ssh/known_hosts
fi

echo "Cleaning done"
exit 0
