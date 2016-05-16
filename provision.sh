#!/usr/bin/env bash

# Default values
VERBOSE=no

function usage(){
    echo "Usage: $0 [--verbose|-v]"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose|-v) VERBOSE=yes;;
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

# [ $VERBOSE = "yes" ] && echo "Creating the SSH config file [in ${SSH_CONFIG}]"
# echo "#####################" > ${SSH_CONFIG}
# echo "### MicroMosler hosts" >> ${SSH_CONFIG}
# echo "#####################" >> ${SSH_CONFIG}
# for name in "${MACHINES[@]}"
# do
#     echo "Host $name $IPPREFIX$((OFFSET + ${MACHINE_IPs[$name]}))" >> ${SSH_CONFIG}
#     echo "     User centos" >> ${SSH_CONFIG}
#     echo "     StrictHostKeyChecking no" >> ${SSH_CONFIG}
#     echo "     UserKnownHostsFile=/dev/null" >> ${SSH_CONFIG}
#     echo "     ForwardAgent yes" >> ${SSH_CONFIG}
# done

for name in "${MACHINES[@]}"
do
    ssh-keyscan $IPPREFIX$((OFFSET + ${MACHINE_IPs[$name]})) >> ~/.ssh/known_hosts
done

[ $VERBOSE = "yes" ] && echo "Creating the ansible config file [in ${ANSIBLE_CFG}]"
cat > ${ANSIBLE_CFG} <<ENDANSIBLECFG
[defaults]
#hostfile       = $INVENTORY
remote_tmp     = ${ANSIBLE_FOLDER}/tmp
#sudo_user      = root
remote_user    = centos
executable     = /bin/bash
#hash_behaviour = merge

[ssh_connection]
#ssh_args= -o ControlMaster=auto -o ControlPersist=60s -F ${SSH_CONFIG}
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
[ $VERBOSE = "yes" ] && echo "Running playbook: ansible/micromosler.yml"
ANSIBLE_CONFIG=${ANSIBLE_CFG} ansible-playbook -s -i $INVENTORY ./ansible/micromosler.yml
# Note: config file overwritten by ANSIBLE_CFG env variable

# Ansible-playbook options: http://linux.die.net/man/1/ansible-playbook
