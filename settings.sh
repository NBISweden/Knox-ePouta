#!/usr/bin/env bash

OS_PROJECT_DOMAIN_ID=default
OS_USER_DOMAIN_ID=default
OS_PROJECT_NAME=mmosler1
OS_TENANT_NAME=mmosler1
OS_AUTH_URL=http://controller:5000/v3
OS_IDENTITY_API_VERSION=3
OS_IMAGE_API_VERSION=2
OS_ENDPOINT_TYPE=internalURL # User internal URLs
    
if [ -f user.rc ]; then
    source user.rc
else
    echo "Error: User credentials not found [user.rc]"
    exit 1;
fi

# 

CLOUDINIT_FOLDER=./cloudinit
ANSIBLE_FOLDER=./ansible

MM_HOME=$HOME/mosler-micro-mosler
TL_HOME=/home/jonas/thinlinc
MOSLER_HOME=/home/jonas/mosler-system-scripts
MOSLER_MISC=/home/jonas/misc/
MOSLER_IMAGES=/home/jonas/mosler-images


PHONE_HOME=10.254.0.1
PORT=12345
IPPREFIX=10.254.0.
OFFSET=51 # I don't know why Pontus wants to offset the IPs

#SSH_CONFIG=${ANSIBLE_FOLDER}/ssh_config.${OS_TENANT_NAME}
ANSIBLE_CFG=${ANSIBLE_FOLDER}/config.${OS_TENANT_NAME}
INVENTORY=${ANSIBLE_FOLDER}/inventory.${OS_TENANT_NAME}

#TENANT_ID=$(openstack project list | awk '/'${OS_TENANT_NAME}'/ {print $2}')
TENANT_ID=32

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
    [openstack-controller]=3 \
    [thinlinc-master]=4 \
    [filsluss]=5 \
    [supernode]=6 \
    [compute1]=7 \
    [compute2]=8 \
    [compute3]=9 \
    [hnas-emulation]=10 \
    [ldap]=11 \
    [networking-node]=12 \
)

declare -A DATA_IPs
DATA_IPs=(\
    [compute1]=110 \
    [compute2]=111 \
    [compute3]=112 \
    [networking-node]=101 \
)

declare -A MACHINE_GROUPS
MACHINE_GROUPS=(\
    [all]="openstack-controller thinlinc-master filsluss supernode compute1 compute2 compute3 hnas-emulation ldap networking-node" \
    [nfs]="supernode filsluss hnas-emulation" \
    [openstack]="openstack-controller supernode networking-node compute1 compute2 compute3" \
    [openstack-compute]="compute1 compute2 compute3" \
)

