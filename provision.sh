#!/usr/bin/env bash

# Default values
VERBOSE=yes
COMMON=yes
OS_COMMON=yes

function usage(){
    echo "Usage: $0 [--quiet|-q] [--no-common] -- ..."
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) VERBOSE=no;;
        --no-common) COMMON=no;;
        --no-os-common) OS_COMMON=no;;
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
cat > ${ANSIBLE_CONFIG} <<ENDANSIBLECFG
[defaults]
hostfile       = $INVENTORY
#remote_tmp     = ${ANSIBLE_FOLDER}/tmp/
#sudo_user      = root
remote_user    = centos
executable     = /bin/bash
#hash_behaviour = merge
log_path       = ${ANSIBLE_FOLDER}/log

[ssh_connection]
pipelining = True
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
mgmt_cidr=${MGMT_CIDR}
ENDINVENTORY

########################################################################
# Aaaaannndddd....cue music!
########################################################################
# ANSIBLE_CONFIG is defined in settings.sh

# if [ $COMMON = "yes" ]; then
#     set -e # exit on erros
#     [ $VERBOSE = "yes" ] && echo "Running playbook: ansible/common.yml (using ${#MACHINES[@]} forks)"
#     ansible-playbook -f ${#MACHINES[@]} -s ./ansible/common.yml 2>&1 > ${ANSIBLE_LOGS}/common $@
# fi

########################################################################

[ $VERBOSE = "yes" ] && echo "Starting the Mosler Images server [in ${MOSLER_IMAGES}]"
pushd ${MOSLER_IMAGES}
fuser -k ${PORT}/tcp
python -m SimpleHTTPServer ${PORT} &
FILE_SERVER=$!
popd

mkdir -p ${ANSIBLE_LOGS}
declare -A ANSIBLE_PIDS
[ $VERBOSE = "yes" ] && echo "Running playbooks (see logs in ${ANSIBLE_LOGS})"
for group in "${!MACHINE_GROUPS[@]}"; do
    [ $group = "all" ] && continue # Skipping that group
    # Note: Using the ANSIBLE_CONFIG env variable
    # Ansible-playbook options: http://linux.die.net/man/1/ansible-playbook
    ansible-playbook -f ${#MACHINES[@]} -s ./ansible/micromosler.yml --tags "$group" 2>&1 > ${ANSIBLE_LOGS}/$group $@ &
    ANSIBLE_PIDS[$group]=$!
done
# Wait for all the ansible calls to finish
[ $VERBOSE = "yes" ] && echo "Waiting for the playbooks to finish"
for job in ${!ANSIBLE_PIDS[@]}; do echo -e "\t* for $job [PID: ${ANSIBLE_PIDS[$job]}]"; done
FAIL=""
for job in ${!ANSIBLE_PIDS[@]}
do
    wait ${ANSIBLE_PIDS[$job]} || FAIL+=" $job"
    echo -e "\t=> $job finished"
done
[ $VERBOSE = "yes" ] && echo "Playbooks finished"
[ -n "$FAIL" ] && echo "Failed playbooks: $FAIL"

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
