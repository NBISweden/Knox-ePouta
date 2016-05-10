#!/usr/bin/env bash

# Default values
VERBOSE=no
NETWORK=no
SG=no

function usage(){
    echo "Usage: $0 [--verbose|-v] [--ipprefix <aaa.bbb.ccc.>] [--with-network] [--with-sg]"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --ipprefix) IPPREFIX=$2; shift ;;
        --with-network) NETWORK=yes;;
        --with-sg) SG=yes;;
        --verbose|-v) VERBOSE=yes;;
        --help|-h) usage; exit 0;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done                                                                                              

# Get credentials and machines settings
source ./settings.sh

#######################################################################


DHCPAGENT_ID=a3edfcfa-c91b-4e24-98d0-51b79d1ee38d
EXTNET_ID=$(neutron net-list | awk '/ public /{print $2}')

if [ $NETWORK = "yes" ]; then

    [ $VERBOSE = "yes" ] && echo "Creating router and networks"

    neutron router-create ${OS_TENANT_NAME}-router
    ROUTER_ID=$(neutron router-list -F id -F name | awk '/ '${OS_TENANT_NAME}-router' / {print $2}')
    
    if [ -z "$ROUTER_ID" ]; then
	echo "Router issues for $proj, skipping."
    else
	neutron router-gateway-set $ROUTER_ID $EXTNET_ID
    fi
    
    # Creating the management and data networks
    neutron net-create ${OS_TENANT_NAME}-mgmt-net
    neutron subnet-create --name ${OS_TENANT_NAME}-mgmt-subnet ${OS_TENANT_NAME}-mgmt-net 172.25.8.0/22 --gateway 172.25.8.1
    # should we have the vlan-transparent flag?
    neutron net-create --vlan-transparent=True ${OS_TENANT_NAME}-data-net
    neutron subnet-create --name ${OS_TENANT_NAME}-data-subnet ${OS_TENANT_NAME}-data-net 10.10.10.0/24
    
    neutron router-interface-add $ROUTER_ID $(neutron subnet-list | awk '/ '${OS_TENANT_NAME}'-mgmt-subnet / {print $2}')
    neutron dhcp-agent-network-add $DHCPAGENT_ID ${OS_TENANT_NAME}-mgmt-net

    [ $VERBOSE = "yes" ] && echo "Creating the floating IPs"
    for machine in "${MACHINES[@]}"; do
	neutron floatingip-create --tenant-id ${TENANT_ID} --floating-ip-address $IPPREFIX$((${MACHINE_IPs[$machine]} + OFFSET)) public
    done

fi # End network config

# Using Cloudinit instead to include several keys at boot time
#nova keypair-add --pub-key "$HOME"/.ssh/id_rsa.pub "${OS_TENANT_NAME}"-key
# Note: nova boot will not use the --key-name flag

if [ $SG = "yes" ]; then
    [ $VERBOSE = "yes" ] && echo "Creating the Security Group: ${OS_TENANT_NAME}-sg"
    neutron security-group-create ${OS_TENANT_NAME}-sg
    neutron security-group-rule-create ${OS_TENANT_NAME}-sg --direction ingress --ethertype ipv4 --protocol icmp 
    neutron security-group-rule-create ${OS_TENANT_NAME}-sg --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 22 --port-range-max 22
    neutron security-group-rule-create ${OS_TENANT_NAME}-sg --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 443 --port-range-max 443
    neutron security-group-rule-create ${OS_TENANT_NAME}-sg --ethertype ipv4 --direction ingress --remote-group-id ${OS_TENANT_NAME}-sg
    neutron security-group-rule-create ${OS_TENANT_NAME}-sg --ethertype ipv4 --direction egress --remote-group-id ${OS_TENANT_NAME}-sg
fi

# TENANT_ID is defined in credentials.sh
MGMT_NET=$(neutron net-list --tenant_id=$TENANT_ID | awk '/ '${OS_TENANT_NAME}-mgmt-net' /{print $2}')
DATA_NET=$(neutron net-list --tenant_id=$TENANT_ID | awk '/ '${OS_TENANT_NAME}-data-net' /{print $2}')

[ $VERBOSE = "yes" ] && echo -e "Management Net: $MGMT_NET\nData Net: $DATA_NET"

if [ -z $MGMT_NET ] || [ -z $DATA_NET ]; then
    echo "Error: Could not find the Management or Data network"
    echo -e "\tMaybe you should re-run with the --with-network --with-sg flags?"
    exit 1
fi

#ROUTER_ID=$(neutron router-list -F id -F name | awk '/ '${OS_TENANT_NAME}-router' / {print $2}')


function boot_machine {
local name=$1
local id=${MACHINE_IPs[$name]}
local flavor=${FLAVORS[$machine]}

mkdir -p ${CLOUDINIT_FOLDER}
cat > ${CLOUDINIT_FOLDER}/vm_init-$id.yml <<ENDCLOUDINIT
#cloud-config
disable_root: true
system_info:
  default_user:
    name: centos
    lock_passwd: true
# Centos is already sudoer
#    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
#    groups: sudo

timezone: Europe/Stockholm

# add each entry to ~/.ssh/authorized_keys for the configured user (ie centos)
ssh_authorized_keys:
  - ssh-dss AAAAB3NzaC1kc3MAAACBAPS8NmjvC0XVOxumjmB8qEzp/Ywz0a1ArVQy0R5KmC0OfF4jLwQlf06G5oxsyx/PhOHyMHcQN8pxoWPfkfjKA8ES8jwveDTN4sprP9wRFKHZvl+DyLvTULcIciw14afHKHx5VvG7gx8Jp9+hcuEyZXO/zP8vrFAFoTf7mU7XYsNFAAAAFQC0cdoL/Wv26mZsoOMO97w5RrV0TwAAAIEAhmijgzvzxHeN0os2vw12ycSn0FyGRWtEPclOfABuDZemX+3wCBle6G/HqO8umZ6OH+oZtcm+b5HAHYx2QXsL9ZG2VvN8hVhZlexa6z9xbYGujD+UHdbA1DKpLnHf7NEeXyyx0uD7vBKj6aPLx1btWNxCtuWRAt9A6VoJ1+ndvboAAACBALRqEh2JZqbMBuUxmVg9QDBG2BYbq+FWd64f0b+lC8kuQuBjPG0htIdrB0LdMZVaAokvA5p5XFckhouvcjECTT/6U+R+oghnN/kFztODKLJScPWPYl0zJkLrAbSQuab7cilLzRA8EZm2DtHu0+Bgvz4v9irVjjU7zIrANtjzjEt3 daz@bils.se
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCj6D2GkvSf47cKP9s/pdwGD5+2VH/xmBhEnDQfxVi9zZ/uEBWdx/7m5fDj7btcRxGgxlbBExu8uwi8rL4ua7VOtUY9TNjlh8fr2GCstFHI3JvnKif4i0zjBRYZI5dXwkC70hZeHAjMhKO4Nlf6SNP8ZIM+SljA8q4E0eAig25+Zdag5oUkbvReKl1H8E6KQOrwzNwKIxYvil+x9mo49qTLqI7Q4xgizxX8i44TRfO0NVS/XhLvNigShEmtQG2Y74qH/cFGe+m6/u17ewfDrxPtoE2ZnQWC7EN9WbFR/hPjrDauMNNCOedHXMZUJ5TSdsyjTPNXVHcgxaXfzHoruQBH jonas@chornholio

runcmd:
  - [ sudo, "sed -i -e '/^PermitRootLogin/s/^.*$/PermitRootLogin no/' /etc/ssh/sshd_config" ]
  - 'echo proxy=http://130.238.7.178:3128/ | sudo tee -a /etc/yum.conf' </dev/null'

write_files:
  - sudo: true
  - owner: root:root
  - path: /etc/hosts
    owner: root:root
    permissions: '0644'
    content: |
      127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
      ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
      # Management network is 192.168.20.0/24
      172.25.8.3 openstack-controller tos1
      172.25.8.5 filsluss
      172.25.8.4 thinlinc-master
      172.25.8.6 supernode tsn
      172.25.8.7 compute1
      172.25.8.8 compute2
      172.25.8.9 compute3
      172.25.8.10 hnas-emulation
      172.25.8.11 ldap

# Yum packages
packages:
    - epel-release
    - lsof
    - strace
    - https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
    - jq
    - tcpdump
    - cloud-utils-growpart

# Yum update
repo_update: true
repo_upgrade: all
package_upgrade: true

final_message: "The system is finally up, after $UPTIME seconds"

ENDCLOUDINIT

# If Data IP is not zero-length
if [ ! -z ${DATA_IPs[$machine]} ]; then
    local DN="--nic net-id=$DATA_NET,v4-fixed-ip=10.10.10.${DATA_IPs[$machine]}"
    cat >> ${CLOUDINIT_FOLDER}/vm_init-$id.yml <<ENDCLOUDINIT
write_files:
  - sudo: true
  - path: /etc/sysconfig/network-scripts/ifcfg-eth0
    owner: root:root
    permissions: '0644'
    content: |
      TYPE=Ethernet
      BOOTPROTO=static
      DEFROUTE=yes
      NAME=eth0
      DEVICE=eth0
      ONBOOT=yes
      IPADDR=192.168.20.<number>
      PREFIX=24
      GATEWAY=192.168.20.1
      NM_CONTROLLED=no

  - path: /etc/sysconfig/network-scripts/ifcfg-eth1
    owner: root:root
    permissions: '0644'
    content: |
      TYPE=Ethernet
      BOOTPROTO=static
      DEFROUTE=no
      NAME=eth1
      DEVICE=eth1
      ONBOOT=yes
      IPADDR=192.168.21.<number>
      PREFIX=24
      #GATEWAY=192.168.21.1
      NM_CONTROLLED=no

  - path: /etc/sysconfig/network-scripts/rule-eth1
    owner: root:root
    permissions: '0644'
    content: |
      to 192.168.21.0/24 lookup thinlink
      from 192.168.21.0/24 lookup thinlink

  - path: /etc/sysconfig/network-scripts/route-eth1
    owner: root:root
    permissions: '0644'
    content: |
      default via 192.168.21.1 dev eth1 table thinlink

runcmd:
  - echo 'Restarting network'
  - systemctl restart network 
ENDCLOUDINIT
fi

# Booting a machine
nova boot \
--flavor $flavor \
--image 'CentOS6' \
--nic net-id=${MGMT_NET},v4-fixed-ip=172.25.8.$id \
$DN \
--security-group ${OS_TENANT_NAME}-sg \
--user-data ${CLOUDINIT_FOLDER}/vm_init-$id.yml \
$name

[ $VERBOSE = "yes" ] && echo -e "\tAssociating floating IP: $IPPREFIX$((id + OFFSET))"
nova floating-ip-associate $name $IPPREFIX$((id + OFFSET))

} # End boot_machine function

# Let's go
for machine in "${MACHINES[@]}"; do boot_machine $machine; done

# # Associate floating IPs (Looping through the keys)
# for i in "${!MACHINES[@]}"
# do
#     [ $VERBOSE = "yes" ] && echo -e "Associating $IPPREFIX$((i + OFFSET)) to ${MACHINES[$i]}"
#     nova floating-ip-associate $machine "$IPPREFIX"$((i + OFFSET))
# done

#INVENTORY=/tmp/inventory-${OS_TENANT_NAME}
INVENTORY=./inventory-${OS_TENANT_NAME}
echo "[all]" > $INVENTORY
for i in "${!MACHINES[@]}"; do echo "$IPPREFIX$((OFFSET + i))" >> $INVENTORY; done

echo -e "\n[filsluss]" >> $INVENTORY
echo $IPPREFIX$OFFSET >> $INVENTORY

echo -e "\n[networking-node]" >> $INVENTORY
echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[networking-node]})) >> $INVENTORY

echo -e "\n[ldap]" >> $INVENTORY
echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[ldap]})) >> $INVENTORY

echo -e "\n[thinlinc-master]" >> $INVENTORY
echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[thinlinc-master]})) >> $INVENTORY

echo -e "\n[openstack-controller]" >> $INVENTORY
echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[openstack-controller]})) >> $INVENTORY

echo -e "\n[supernode]" >> $INVENTORY
echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[supernode]})) >> $INVENTORY

echo -e "\n[compute]" >> $INVENTORY
for i in {1..3}; do echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[compute$i]})) >> $INVENTORY; done

echo -e "\n[hnas-emulation]" >> $INVENTORY
echo $IPPREFIX$((OFFSET + ${MACHINE_IPs[hnas-emulation]})) >> $INVENTORY


# # Wait for all hosts
# while true; do
#   for p in {0..9}; do
#     ssh -oStrictHostKeyChecking=no -tt centos@"$IPPREFIX""$((OFFSET+p))" echo finished 
#   done | grep -c finished | grep -q 10 && break
# done


# # Here because in cleanup we don't care about IPs (we don't care enough to pick up the information)
# for p in {0..9}; do 
#   ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IPPREFIX""$((OFFSET+p))"
  
#   ssh -oStrictHostKeyChecking=no -tt centos@"$IPPREFIX""$((OFFSET+p))" 'echo proxy=http://130.238.7.178:3128/ | sudo tee -a /etc/yum.conf' </dev/null
#   ssh -oStrictHostKeyChecking=no -tt centos@"$IPPREFIX""$((OFFSET+p))"  'sudo yum -y install epel-release'  < /dev/null
#  ssh -oStrictHostKeyChecking=no -tt centos@"$IPPREFIX""$((OFFSET+p))"  'sudo yum -y install cloud-utils-growpart && sudo growpart /dev/vda 1 && sudo shutdown -r now'  < /dev/null
# done

# # Wait for all hosts
# while true; do
#   for p in {0..9}; do
#     ssh -oStrictHostKeyChecking=no -tt centos@"$IPPREFIX""$((OFFSET+p))" echo finished 
#   done | grep -c finished | grep -q 10 && break
# done



# # We want to set up right away.

# ansible-playbook -u centos -i /tmp/inventory-"${OS_TENANT_NAME}" ./playbooks/micromosler.yml

