#!/usr/bin/env bash

# Default values
VERBOSE=no
PACKAGES=no

function usage(){
    echo "Usage: $0 [--verbose|-v] [--with-packages] -- ..."
    echo "       the ... arguments are passed on to the ansible call"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose|-v) VERBOSE=yes;;
        --with-packages) PACKAGES=yes;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done                                                                                              

# Get credentials and machines settings
source ./settings.sh

# Note: Should exit the script if machines not yet available
# Should I test with an ssh connection (with timeout?)

#############################################
## Calling ansible for the MicroMosler setup
#############################################

[ $VERBOSE = "yes" ] && echo -e "Adding the SSH keys to ~/.ssh/known_hosts"
if [ -f ~/.ssh/known_hosts ]; then
    # Cut the matching keys out
    # for name in "${MACHINES[@]}"; do sed -i "/${FLOATING_IPs[$name]}/d" ~/.ssh/known_hosts; done
    sed -n -i "/${FLOATING_CIDR%0/24}/d" ~/.ssh/known_hosts
else 
    touch ~/.ssh/known_hosts
fi
# Adding the keys to the known_hosts file
for name in "${MACHINES[@]}"; do ssh-keyscan -4 ${FLOATING_IPs[$name]} >> ~/.ssh/known_hosts 2>/dev/null; done
# Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.

[ $VERBOSE = "yes" ] && echo "Creating the ansible config file [in ${ANSIBLE_CFG}]"
cat > ${ANSIBLE_CFG} <<ENDANSIBLECFG
[defaults]
hostfile       = $INVENTORY
#remote_tmp     = ${ANSIBLE_FOLDER}/tmp/
#sudo_user      = root
remote_user    = centos
executable     = /bin/bash
#hash_behaviour = merge

[ssh_connection]
ssh_args= -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardAgent=yes
# I know, I know, Forwarding the ssh-Agent is a bad idea. That'll do it for the moment.
ENDANSIBLECFG

[ $VERBOSE = "yes" ] && echo "Creating the inventory [in $INVENTORY]"
echo "" > $INVENTORY
for name in "${MACHINES[@]}"; do echo "$name ansible_ssh_host=${FLOATING_IPs[$name]}" >> $INVENTORY; done
for group in "${!MACHINE_GROUPS[@]}"; do
    echo -e "\n[$group]" >> $INVENTORY
    for machine in ${MACHINE_GROUPS[$group]}; do echo "$machine" >> $INVENTORY; done
done
# Make sure TL_HOME and MOSLER_MISC end with a slash, or several!
cat >> $INVENTORY <<ENDINVENTORY

[all:vars]
mm_home=${MM_HOME}
tl_home=${TL_HOME}/
mosler_home=${MOSLER_HOME}
mosler_misc=${MOSLER_MISC}/
mosler_images=${MOSLER_IMAGES}
mosler_images_url=http://${FLOATING_GATEWAY}:$PORT
db_server=${MACHINE_IPs[openstack-controller]}
ENDINVENTORY

[ $VERBOSE = "yes" ] && echo "Starting the Mosler Images server [in ${MOSLER_IMAGES}]"
pushd ${MOSLER_IMAGES}
fuser -k ${PORT}/tcp
python -m SimpleHTTPServer ${PORT} &
FILE_SERVER=$!
popd

# Aaaaannndddd....cue music!
if [ $PACKAGES = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Running playbook: ansible/packages.yml"
    set -e # exit on errors
    ANSIBLE_CONFIG=${ANSIBLE_CFG} ansible-playbook -s ./ansible/packages.yml $@
fi

[ $VERBOSE = "yes" ] && echo "Running playbook: ansible/micromosler.yml (using config file: ${ANSIBLE_CFG}) (using ${#MACHINES[@]} forks)"
ANSIBLE_CONFIG=${ANSIBLE_CFG} ansible-playbook -s ./ansible/micromosler.yml $@
# Note: config file overwritten by ANSIBLE_CFG env variable
# Ansible-playbook options: http://linux.die.net/man/1/ansible-playbook

[ $VERBOSE = "yes" ] && echo "Killing the Mosler Images server [PID: ${FILE_SERVER}]"
kill ${FILE_SERVER}

# Note: If the ansible script finishes before the Glance image are
# pulled from the SimpleHTTPServer, then re-write the server using,
# either a timeout, or some logic that checks that all the images
# downloads are completed.  Like checking in the log file (or stderr
# maybe) that the requests are completed, or making the request flags
# itself when completed and we'd check if we have 3 flags...  That is
# not super complex, but we might not need to do it.
# See: http://code.activestate.com/recipes/499376-basehttpserver-with-socket-timeout/
# and: http://code.activestate.com/recipes/425210/ 
