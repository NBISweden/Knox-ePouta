#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/../settings/common.sh

# Default values
KE_VLAN=1203
MGMT_ALLOCATION_START=10.101.128.2
MGMT_ALLOCATION_END=10.101.255.254

function usage {
    echo "Usage: ${KE_CMD:-$0} [options]"
    echo -e "\noptions are"
    echo -e "\t--quiet,-q            \tRemoves the verbose output"
    echo -e "\t--help,-h             \tOutputs this message and exits"
    echo -e "\t-- ...                \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) VERBOSE=no;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

_CLOUD=knox

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
[ $VERBOSE == 'no' ] && exec 1>${KE_TMP}/init.log
ORG_FD1=$(tty)

source $(dirname ${BASH_SOURCE[0]})/../settings/common.sh

#######################################################################
# Preparing the network components

echo "Creating routers and networks"

MGMT_ROUTER_ID=$(neutron router-create ${OS_TENANT_NAME}-mgmt-router | awk '/ id / { print $4 }')
echo qrouter-$MGMT_ROUTER_ID > ${KE_TMP}/netns

# if [ -z "$MGMT_ROUTER_ID" ]; then
# 	echo "Router issues. Exiting..."
#   exit 1
# fi

# Creating the management and data networks
neutron net-create --provider:network_type vlan --provider:physical_network vlan --provider:segmentation_id ${KE_VLAN} ${OS_TENANT_NAME}-mgmt-net >/dev/null
neutron subnet-create --name ${OS_TENANT_NAME}-mgmt-subnet ${OS_TENANT_NAME}-mgmt-net --allocation-pool start=${MGMT_ALLOCATION_START},end=${MGMT_ALLOCATION_END} --gateway ${MGMT_GATEWAY} ${MGMT_CIDR} >/dev/null # --disable-dhcp
neutron router-interface-add ${OS_TENANT_NAME}-mgmt-router ${OS_TENANT_NAME}-mgmt-subnet >/dev/null

echo "Creating the Security Group: ${OS_TENANT_NAME}-sg"
nova secgroup-create ${OS_TENANT_NAME}-sg "Security Group for ${OS_TENANT_NAME}" >/dev/null
nova secgroup-add-rule ${OS_TENANT_NAME}-sg icmp  -1    -1 ${MGMT_CIDR}          >/dev/null
nova secgroup-add-rule ${OS_TENANT_NAME}-sg tcp    1 65535 ${MGMT_CIDR}          >/dev/null

echo "Setting the quotas"
FACTOR=2
nova quota-update --instances $((10 * FACTOR)) --ram $((51200 * FACTOR)) ${TENANT_ID} >/dev/null

# echo "Adding flavors"
# nova flavor-create --is-public false mm.compute   10 7200 80 4
# nova flavor-create --is-public false mm.storage   11 2048 160 1
# nova flavor-create --is-public false mm.supernode 12 2048 20 1

