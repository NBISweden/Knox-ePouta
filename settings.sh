#!/usr/bin/env bash

export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=mmosler1
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export OS_ENDPOINT_TYPE=internalURL # User internal URLs

HERE=$(dirname ${BASH_SOURCE[0]})
if [ -f $HERE/user.rc ]; then
    source $HERE/user.rc
else
    echo "ERROR: User credentials not found [$HERE/user.rc]"
    exit 1;
fi

if [ -z $OS_TENANT_NAME ]; then
    echo "ERROR: No tenant name found in [$HERE/user.rc]"
    echo "Exiting..."
    exit 1;
fi

# 
TENANT_ID=$(openstack project list | awk '/'${OS_TENANT_NAME}'/ {print $2}')
CHECK=$(openstack role assignment list --user ${OS_USERNAME} --role admin --project ${OS_TENANT_NAME})
if [ $? -ne 0 ]; then
    echo "ERROR: $CHECK"
    echo -e "\nThe user ${OS_USERNAME} does not seem to have the 'admin' role for the project ${OS_TENANT_NAME}"
    echo "Exiting..."
    exit 1
fi

#################################################################

CLOUDINIT_FOLDER=./cloudinit
ANSIBLE_FOLDER=./ansible

MM_HOME=$HOME/mosler-micro-mosler
TL_HOME=/home/jonas/thinlinc
MOSLER_HOME=/home/jonas/mosler-system-scripts
MOSLER_MISC=/home/jonas/misc
MOSLER_IMAGES=/home/jonas/mosler-images

PHONE_HOME=10.254.0.1
PORT=12345

#SSH_CONFIG=${ANSIBLE_FOLDER}/ssh_config.${OS_TENANT_NAME}
ANSIBLE_CFG=${ANSIBLE_FOLDER}/config.${OS_TENANT_NAME}
INVENTORY=${ANSIBLE_FOLDER}/inventory.${OS_TENANT_NAME}

#################################################################

# Declaring the machines
# Arrays are one-dimensional only. Tyvärr!
declare -a MACHINES
MACHINES=('openstack-controller' 'thinlinc-master' 'filsluss' 'supernode' 'compute1' 'compute2' 'compute3' 'hnas-emulation' 'ldap' 'networking-node')

declare -A FLAVORS
FLAVORS=(\
    [openstack-controller]=m1.small \
    [thinlinc-master]=m1.small \
    [filsluss]=m1.small \
    [supernode]=m1.small \
    [compute1]=m1.large \
    [compute2]=m1.large \
    [compute3]=m1.large \
    [hnas-emulation]=m1.small \
    [ldap]=m1.small \
    [networking-node]=m1.small \
)

declare -A MACHINE_IPs
MACHINE_IPs=(\
    [openstack-controller]=172.25.8.3 \
    [thinlinc-master]=172.25.8.4 \
    [filsluss]=172.25.8.5 \
    [supernode]=172.25.8.6 \
    [compute1]=172.25.8.7 \
    [compute2]=172.25.8.8 \
    [compute3]=172.25.8.9 \
    [hnas-emulation]=172.25.8.10 \
    [ldap]=172.25.8.11 \
    [networking-node]=172.25.8.12 \
)
MGMT_GATEWAY=172.25.8.1
MGMT_CIDR=172.25.8.0/22

declare -A DATA_IPs
DATA_IPs=(\
    [compute1]=10.10.10.110 \
    [compute2]=10.10.10.111 \
    [compute3]=10.10.10.112 \
    [networking-node]=10.10.10.101 \
)
DATA_GATEWAY=10.10.10.1
DATA_CIDR=10.10.10.0/24

declare -A FLOATING_IPs
FLOATING_IPs=(\
    [openstack-controller]=10.254.0.54 \
    [thinlinc-master]=10.254.0.55 \
    [filsluss]=10.254.0.56 \
    [supernode]=10.254.0.57 \
    [compute1]=10.254.0.58 \
    [compute2]=10.254.0.59 \
    [compute3]=10.254.0.60 \
    [hnas-emulation]=10.254.0.61 \
    [ldap]=10.254.0.62 \
    [networking-node]=10.254.0.63 \
)
FLOATING_GATEWAY=10.254.0.1
FLOATING_CIDR=10.254.0.0/24

declare -A MACHINE_GROUPS
MACHINE_GROUPS=(\
    [all]="openstack-controller thinlinc-master filsluss supernode compute1 compute2 compute3 hnas-emulation ldap networking-node" \
    [nfs]="supernode filsluss hnas-emulation" \
    [openstack]="openstack-controller supernode networking-node compute1 compute2 compute3" \
    [openstack-compute]="compute1 compute2 compute3" \
)

