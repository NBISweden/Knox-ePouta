#!/usr/bin/env bash

# Default values
NETWORKS=no
SG=no
VERBOSE=no

function usage(){
    echo "Usage: $0 [--verbose|-v] [--with-networks] [--with-sg]"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --with-networks) NETWORKS=yes;;
        --with-sg) SG=yes;;
        --verbose|-v) VERBOSE=yes;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done                                                                                              

# Get credentials and machines settings
source ./settings.sh

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
if [ $NETWORKS = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Cleaning the network information"

    [ $VERBOSE = "yes" ] && echo "Disconnecting the router from the management subnet"
    neutron router-interface-delete ${OS_TENANT_NAME}-router ${OS_TENANT_NAME}-mgmt-subnet

    [ $VERBOSE = "yes" ] && echo "Deleting networks and subnets"
    neutron subnet-delete ${OS_TENANT_NAME}-mgmt-subnet
    neutron subnet-delete ${OS_TENANT_NAME}-data-subnet
    neutron net-delete ${OS_TENANT_NAME}-mgmt-net
    neutron net-delete ${OS_TENANT_NAME}-data-net

    [ $VERBOSE = "yes" ] && echo "Deleting router"
    neutron router-delete ${OS_TENANT_NAME}-mgmt-router
    neutron router-delete ${OS_TENANT_NAME}-data-router

    [ $VERBOSE = "yes" ] && echo "Deleting floating IPs"
    for machine in "${MACHINES[@]}"; do echo neutron floatingip-delete $IPPREFIX$((${MACHINE_IPs[$machine]} + OFFSET)); done

fi # End cleaning the networks

# Cleaning the security group
if [ $SG = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Cleaning security group: ${OS_TENANT_NAME}-sg"
    neutron security-group-delete ${OS_TENANT_NAME}-sg
fi

echo "Cleaning done"
exit 0
