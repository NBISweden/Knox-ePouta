#!/usr/bin/env bash

# Default values
VERBOSE=no
PACKAGES=no

function usage(){
    echo "Usage: $0 [--verbose|-v] [--with-packages]"
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

#############################################
## Calling ansible for the MicroMosler setup
#############################################

[ $VERBOSE = "yes" ] && echo -e "Adding the SSH keys to ~/.ssh/known_hosts"
if [ -f ~/.ssh/known_hosts ]; then
    # Cut the matching keys out
    #for name in "${MACHINES[@]}"; do sed -i "/$IPPREFIX$((OFFSET + ${MACHINE_IPs[$name]}))/d" ~/.ssh/known_hosts; done
    sed -n -i "/${IPPREFIX}/d" ~/.ssh/known_hosts
else 
    touch ~/.ssh/known_hosts
fi
# Adding the keys to the known_hosts file
for name in "${MACHINES[@]}"; do ssh-keyscan -4 $IPPREFIX$((OFFSET + ${MACHINE_IPs[$name]})) >> ~/.ssh/known_hosts 2>/dev/null; done
# Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.

[ $VERBOSE = "yes" ] && echo "Creating the ansible config file [in ${ANSIBLE_CFG}]"
cat > ${ANSIBLE_CFG} <<ENDANSIBLECFG
[defaults]
hostfile       = $INVENTORY
remote_tmp     = ${ANSIBLE_FOLDER}/tmp/
#sudo_user      = root
remote_user    = centos
executable     = /bin/bash
#hash_behaviour = merge

[ssh_connection]
ssh_args= -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ForwardAgent=yes
ENDANSIBLECFG

[ $VERBOSE = "yes" ] && echo "Creating the inventory [in $INVENTORY]"
echo "" > $INVENTORY
for name in "${MACHINES[@]}"; do echo "$name ansible_ssh_host=$IPPREFIX$((OFFSET + ${MACHINE_IPs[$name]}))" >> $INVENTORY; done
echo -e "\n[all]" >> $INVENTORY
for name in "${MACHINES[@]}"; do echo "$name" >> $INVENTORY; done
cat >> $INVENTORY <<ENDINVENTORY

[nfs]
supernode
filsluss
hnas-emulation

[openstack]
openstack-controller
supernode
networking-node
compute1
compute2
compute3

[openstack-compute]
compute1
compute2
compute3

[all:vars]
mm_home=$HOME/mosler-micro-mosler
tl_home=$HOME/thinlinc
mosler_home=$HOME/mosler-system-scripts
mosler_misc=$HOME/misc/
mosler_images=$HOME/mosler-images
ENDINVENTORY

# Aaaaannndddd....cue music!
if [ $PACKAGES = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Running playbook: ansible/packages.yml"
    ANSIBLE_CONFIG=${ANSIBLE_CFG} ansible-playbook -s ./ansible/packages.yml
fi

[ $VERBOSE = "yes" ] && echo "Running playbook: ansible/micromosler.yml (using config file: ${ANSIBLE_CFG})"
ANSIBLE_CONFIG=${ANSIBLE_CFG} ansible-playbook -s ./ansible/micromosler.yml
# Note: config file overwritten by ANSIBLE_CFG env variable
# Ansible-playbook options: http://linux.die.net/man/1/ansible-playbook
