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

[ ! -r ${SSH_CONFIG} ] && cat > ${SSH_CONFIG} <<ENDSSHCFG
Host ${MGMT_CIDR%0.0/16}*.*
	User centos
	StrictHostKeyChecking no
	UserKnownHostsFile ${SSH_KNOWN_HOSTS}
ENDSSHCFG

NETNS=$(<${MM_TMP}/${OS_TENANT_NAME}-mgmt-router) # bash only
[ -z $NETNS ] && echo "Unknown virtual router: ${OS_TENANT_NAME}-mgmt-router" && exit 1

if [[ $host == 'epouta-'* ]]; then
    _IP=${MGMT_CIDR%0.0/16}${host#epouta-} # 10.101. and the number after 'epouta-'
else
    [ -z "${MACHINE_IPs[$host]}" ] && echo "Unknown machine: $host" && exit 1
    _IP=${MACHINE_IPs[$host]}
fi

echo "Connecting to $host [$_IP]"
#sudo -E ip netns exec $NETNS nc -4 -z -w 1 $_IP 22 || { echo "Unable to contact port 22"; exit 1; }
sudo -E ip netns exec $NETNS ssh $@ -t -F ${SSH_CONFIG} $_IP

