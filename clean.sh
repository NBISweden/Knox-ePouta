#!/usr/bin/env bash

# Default values
NETWORKS=yes
SG=yes
VERBOSE=no

function usage(){
    echo "Usage: $0 [--verbose|-v] [--skip-networks] [--skip-sg]"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-networks) NETWORKS=no;;
        --skip-sg) SG=no;;
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
echo "Cleaning running machines"
function delete_machine {
    local machine=$1
    [ $VERBOSE = "yes" ] && echo "Deleting VM: $machine"
    nova delete $machine
}

for machine in "${MACHINES[@]}"; do delete_machine $machine; done

# Cleaning the network information
if [ $NETWORKS = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Cleaning the network information"

    neutron router-interface-delete ${OS_TENANT_NAME}-router ${OS_TENANT_NAME}-mgmt-subnet

    neutron subnet-delete ${OS_TENANT_NAME}-mgmt-subnet
    neutron subnet-delete ${OS_TENANT_NAME}-data-subnet
    neutron net-delete ${OS_TENANT_NAME}-mgmt-net
    neutron net-delete ${OS_TENANT_NAME}-data-net

    neutron router-delete ${OS_TENANT_NAME}-router

fi # End cleaning the networks

# Cleaning the security group
if [ $SG = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Cleaning security group: ${OS_TENANT_NAME}-sg"
    neutron security-group-delete ${OS_TENANT_NAME}-sg
fi

echo "Cleaning done"
exit 0
