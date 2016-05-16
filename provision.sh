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

[ $VERBOSE = "yes" ] && echo "Creating the SSH config file [in ${SSH_CONFIG}]"
echo '' > ${SSH_CONFIG}
for machine in "${MACHINES[@]}"; do
    cat >> ${SSH_CONFIG} <<EOF
##################################################
Host $IPPREFIX$((${MACHINE_IPs[$machine]} + OFFSET))
     User centos
     StrictHostKeyChecking no
     UserKnownHostsFile=/dev/null
EOF
done

echo "[all]" > $INVENTORY
for name in "${MACHINES[@]}"; do echo "$IPPREFIX$((OFFSET + ${MACHINE_IPs[$name]}))" >> $INVENTORY; done
cat >> $INVENTORY <<ENDINVENTORY

[filsluss]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[filsluss]}))

[networking-node]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[networking-node]}))

[ldap]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[ldap]}))

[thinlinc-master]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[thinlinc-master]}))

[openstack-controller]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[openstack-controller]}))

[supernode]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[supernode]}))
 
[hnas-emulation]
$IPPREFIX$((OFFSET + ${MACHINE_IPs[hnas-emulation]}))

[compute]
ENDINVENTORY
for i in {1..3}; do echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[compute$i]})) >> $INVENTORY; done
cat >> $INVENTORY <<ENDINVENTORY
[ssh_connection]
ssh_args = -F ${SSH_CONFIG}

ansible_user = centos
ansible_ssh_user = centos # for older versions
#ansible_ssh_common_args
ansible_ssh_extra_args = -F ${SSH_CONFIG}

[all:vars]
mm_home: "{{ lookup('env','HOME') }}/mosler-micro-mosler"
tl_home: "{{ lookup('env','HOME') }}/thinlinc"
mosler_home: "{{ lookup('env','HOME') }}/mosler-system-scripts"
mosler_misc: "{{ lookup('env','HOME') }}/misc/"
mosler_images: "{{ lookup('env','HOME') }}/mosler-images"
ENDINVENTORY


# Aaaaannndddd....cue music!
[ $VERBOSE = "yes" ] && echo "Running ansible playbook"
ansible-playbook -s -u centos -i $INVENTORY ./playbooks/micromosler.yml

# Ansible-playbook options: http://linux.die.net/man/1/ansible-playbook
