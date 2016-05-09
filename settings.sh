#!/bin/bash

export OS_PROJECT_DOMAIN_ID=default
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_NAME=mmosler1
export OS_TENANT_NAME=mmosler1
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export OS_ENDPOINT_TYPE=internalURL # User internal URLs
    
if [ -f user.rc ]; then
    source user.rc
else
    echo "Error: User credentials not found [user.rc]"
    exit 1;
fi

TENANT_ID=$(openstack project list | awk '/'${OS_TENANT_NAME}'/ {print $2}')

# Declaring the machines names

declare -a MACHINES
MACHINES=(
    (openstack-controller 3 'm1.small') 
    (thinlinc-master      4 'm1.small')
    (filsluss             5 'm1.small')
    (supernode            6 'm1.small')
    (compute1             7 'm1.large')
    (compute2             8 'm1.large' 111)
    (compute2             9 'm1.large' 112)
    (hnas-emulation      10 'm1.small')
    (ldap                11 'm1.small')
    (networking-node     12 'm1.small' 101)
    )
