#!/usr/bin/env bash

# Get credentials and machines settings
source ./settings.sh

# Default values
_ALL=no

function usage(){
    local defaults=${MACHINES[@]}
    echo "Usage: $0 [options]"
    echo -e "\noptions are"
    echo -e "\t--quiet,-q       \tRemoves the verbose output"
    echo -e "\t--help,-h        \tOutputs this message and exits"
    echo -e "\t-- ...           \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --all|-a) _ALL=yes;;
        --quiet|-q) VERBOSE=no;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done


#######################################################################

TENANT_ID=$(openstack project list | awk '/'${OS_TENANT_NAME}'/ {print $2}')
# Checking if the user is admin for that tenant
CHECK=$(openstack role assignment list --user ${OS_USERNAME} --role admin --project ${OS_TENANT_NAME})
if [ $? -ne 0 ] || [ -z "$CHECK" ]; then
    echo "ERROR: $CHECK"
    echo -e "\nThe user ${OS_USERNAME} does not seem to have the 'admin' role for the project ${OS_TENANT_NAME}"
    echo "Exiting..."
    exit 1
fi

MGMT_NET=$(neutron net-list --tenant_id=$TENANT_ID | awk '/ '${OS_TENANT_NAME}-mgmt-net' /{print $2}')

if [ -z $MGMT_NET ]; then
    echo "Error: Could not find the Management network"
    # TODO: fix so the network is prepared too, and not in init.sh
    # echo -e "\tMaybe you should re-run with the --all flags?"
    exit 1
fi

mkdir -p ${INIT_TMP}

# [ "$VERBOSE" = "yes" ] && echo "Creating the floating IPs"
# FLOATING_PREFIX=${FLOATING_CIDR%0/24}
# _IP=100

# while neutron floatingip-list -F floating_ip_address | grep ${FLOATING_PREFIX}${_IP}; do
#     _IP=$((_IP + 1))
# done
# neutron floatingip-create --tenant-id ${TENANT_ID} --floating-ip-address ${FLOATING_PREFIX}${_IP} public

cat > ${INIT_TMP}/vm_prepare.yml <<ENDCLOUDINIT
#cloud-config
bootcmd:
  - echo 'Europe/Stockholm' > /etc/timezone
  - if grep -q 'proxy=.*' /etc/yum.conf; then sed -i 's/proxy=.*/proxy=http:\/\/130.238.7.178:3128\//g' /etc/yum.conf; else echo 'proxy=http://130.238.7.178:3128' >> /etc/yum.conf; fi

runcmd:
  - echo "Installing the EPEL repo" && yum -y install epel-release
  - echo "Upgrading system" && yum -y update
  - echo "Installing packages we always want" && yum -y install lsof strace jq tcpdump cloud-utils-growpart
  - echo "Cloudinit phone home" && curl http://${PHONE_HOME}:$PORT/prepare/ready > /dev/null || true
ENDCLOUDINIT

cat > ${INIT_TMP}/prepare.py <<ENDREST
#!/usr/bin/env python

import web
import sys

urls = ('/prepare/ready', 'ready')

class ready:
    def GET(self):
        # When we hit that URL, the 'prepare' VM is ready
        # so we should exit
        sys.exit(0)

if __name__ == "__main__":
    web.config.debug = False
    app = web.application(urls, globals())
    app.run()

ENDREST

[ "$VERBOSE" = "yes" ] && echo "Starting the REST phone home server"
fuser -k $PORT/tcp
python ${INIT_TMP}/prepare.py $PORT &
REST_PID=$!

# Booting a machine, getting an temporary ip from DHCP
# No need to add ssh-keys, since we won't log onto it
nova boot --flavor 'm1.small' --image 'CentOS6' --nic net-id=${MGMT_NET} --user-data ${INIT_TMP}/vm_prepare.yml --poll prepare

# For the moment, I delete the image, assuming there is one.
# Otherwise, I check if the snapshots have that name,
# loop through, get each ID, and delete those.
[ "$VERBOSE" = "yes" ] && echo "Deleting the CentOS6-micromosler snapshot"
nova image-delete CentOS6-micromosler

[ "$VERBOSE" = "yes" ] && echo "Waiting for the 'prepare' VM to be ready."
wait ${REST_PID}
[ "$VERBOSE" = "yes" ] && echo "The 'prepare' VM just phoned home."

[ "$VERBOSE" = "yes" ] && echo "Creating the CentOS-micromosler snapshot"
nova image-create --poll prepare 'CentOS6-micromosler'

echo "Preparation done"
