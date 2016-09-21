#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings.sh

function usage {
    echo "Usage: ${MM_CMD:-$0} [--help|-h] <machine>"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0;;
	hnas|nfs) host='storage';;
        --) shift; break;;
        *) host=$1;;
    esac
    shift
done

[ -z $host ] && usage && exit 1

if [[ $host == epouta* ]]; then

    _IP=${EPOUTA_IPs[$host]}
    [ -z $_IP ] && echo "Unknown epouta machine: $host" && exit 1

    [ -f ${MM_TMP}/ssh_config_epouta ] && CONF="-F ${MM_TMP}/ssh_config_epouta"

    if [ -r ${MM_TMP}/${OS_TENANT_NAME}-mgmt-router ]; then
	NETNS=$(<${MM_TMP}/${OS_TENANT_NAME}-mgmt-router) # bash only
    else
	NETNS=qrouter-$(neutron router-list | awk "/${OS_TENANT_NAME}-mgmt-router/ {print \$2}")
	echo $NETNS > ${MM_TMP}/${OS_TENANT_NAME}-mgmt-router
    fi
    [ -z $NETNS ] && echo "Unknown virtual router: ${OS_TENANT_NAME}-mgmt-router" && exit 1

    echo "Connecting to $host [$_IP]"
    sudo ip netns exec $NETNS ssh $@ -t $CONF $_IP 'sudo bash'

else

    _IP=${FLOATING_IPs[$host]}
    [ -z $_IP ] && echo "Unknown machine: $host" && exit 1

    [ -f ${MM_TMP}/ssh_config ] && CONF="-F ${MM_TMP}/ssh_config"

    echo "Connecting to $host [$_IP]"
    ssh $@ -t $CONF $_IP 'sudo bash'
fi
