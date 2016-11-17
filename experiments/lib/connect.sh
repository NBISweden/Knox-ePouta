#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings/common.sh

function usage {
    echo "Usage: ${KE_CMD:-$0} [--help|-h] <machine>"
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

############################################
[ -z "${MACHINE_IPs[$host]}" ] && echo "Unknown machine: $host" && exit 1
_IP=${MACHINE_IPs[$host]}

############################################
source $(dirname ${BASH_SOURCE[0]})/netns.sh

echo "Connecting to $host [$_IP]"
#nc -4 -z -w 1 $_IP 22 || { echo "Unable to contact port 22"; exit 1; }
ssh $@ -t -F ${SSH_CONFIG} $_IP

