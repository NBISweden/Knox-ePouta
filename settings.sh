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

export VERBOSE=yes

#################################################################
# Making these variables immutable
# Note: Can source this file several times

[ -n "$MM_HOME" ]       || readonly MM_HOME=$HOME/_micromosler/mosler-micro-mosler
[ -n "$TL_HOME" ]       || readonly TL_HOME=/home/jonas/thinlinc
[ -n "$MOSLER_HOME" ]   || readonly MOSLER_HOME=/home/jonas/mosler-system-scripts
[ -n "$MOSLER_MISC" ]   || readonly MOSLER_MISC=/home/jonas/misc
[ -n "$MOSLER_IMAGES" ] || readonly MOSLER_IMAGES=/home/jonas/mosler-images

[ -n "$INIT_TMP" ]      || readonly INIT_TMP=${MM_HOME}/tmp/init
[ -n "$PROVISION_TMP" ] || readonly PROVISION_TMP=${MM_HOME}/tmp/provision

export TL_HOME MOSLER_HOME MOSLER_MISC MOSLER_IMAGES
export INIT_TMP PROVISION_TMP

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

PHONE_HOME=${FLOATING_GATEWAY}
PORT=12345

########################################
declare -A PROVISION
PROVISION=(\
    [openstack-controller]=openstack-controller \
    [thinlinc-master]=thinlinc \
    [filsluss]=storage \
    [supernode]=supernode \
    [compute1]=openstack-compute \
    [compute2]=openstack-compute \
    [compute3]=openstack-compute \
    [hnas-emulation]=storage \
    [ldap]=ldap \
    [networking-node]=openstack-network \
)

########################################
export SSH_CONFIG=${PROVISION_TMP}/ssh_config.${OS_TENANT_NAME}
function mm_connect {
    local host=$1
    [ -f ${SSH_CONFIG} ] && CONF="-F ${SSH_CONFIG}"
    if [ -n "${FLOATING_IPs[$host]}" ]; then
	ssh $CONF ${FLOATING_IPs[$host]}
    else
	echo "Unknown machine: $host"
    fi
}
