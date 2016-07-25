#!/bin/sh 

set -e -x
source /root/.keystonerc

if ! glance image-show cirros &>/dev/null; then
    glance image-create --disk-format qcow2 --container-format bare --is-public True --name "cirros" --file /home/centos/vault/cirros.img 
fi

PROJECT_NAME=TEST

# If already exists
keystone tenant-get ${PROJECT_NAME} &>/dev/null && echo "${PROJECT_NAME} already exists" && exit 1

keystone tenant-create --name ${PROJECT_NAME}
keystone user-role-add --user admin --role admin --tenant ${PROJECT_NAME}

export OS_TENANT_NAME=${PROJECT_NAME}

neutron net-create ${PROJECT_NAME}-net
neutron router-create ${PROJECT_NAME}-router
neutron router-gateway-set ${PROJECT_NAME}-router public-net
neutron subnet-create --name ${PROJECT_NAME}-subnet --gateway 192.168.10.1 --enable-dhcp ${PROJECT_NAME}-net 192.168.10.0/24
neutron router-interface-add ${PROJECT_NAME}-router ${PROJECT_NAME}-subnet

if [ ! -e ~/ssh_key.${PROJECT_NAME} ] || [ -e ~/ssh_key.${PROJECT_NAME}.pub ]; then
    rm -f ~/ssh_key.${PROJECT_NAME} ~/ssh_key.${PROJECT_NAME}.pub
    ssh-keygen -q -t rsa -N "" -f ~/ssh_key.${PROJECT_NAME} -C ${PROJECT_NAME}
fi
nova keypair-add --pub-key ~/ssh_key.${PROJECT_NAME}.pub ${PROJECT_NAME}-key

nova secgroup-create ${PROJECT_NAME}-mosler_default "${PROJECT_NAME} secgroup"
nova secgroup-add-rule ${PROJECT_NAME}-mosler_default tcp 22 22 0.0.0.0/0
nova secgroup-add-rule ${PROJECT_NAME}-mosler_default icmp -1 -1 0.0.0.0/0

nova boot --key-name ${PROJECT_NAME}-key --flavor mosler.1core --image cirros \
--nic net-id=$(neutron net-list | awk '/ '${PROJECT_NAME}'-net /{print $2}') \
--availability-zone serv-login --security-groups ${PROJECT_NAME}-mosler_default \
${PROJECT_NAME}-service-node
nova boot --key-name ${PROJECT_NAME}-key --flavor mosler.1core --image cirros \
--nic net-id=$(neutron net-list | awk '/ '${PROJECT_NAME}'-net /{print $2}') \
--availability-zone serv-login --security-groups ${PROJECT_NAME}-mosler_default \
${PROJECT_NAME}-login-node
nova boot --key-name ${PROJECT_NAME}-key --flavor mosler.1core --image cirros \
--nic net-id=$(neutron net-list | awk '/ '${PROJECT_NAME}'-net /{print $2}') \
--availability-zone nova --security-groups ${PROJECT_NAME}-mosler_default \
${PROJECT_NAME}-compute-node

FIP=$(neutron floatingip-create public-net | awk '/ floating_ip_address /{print $4}')
nova floating-ip-associate ${PROJECT_NAME}-login-node $FIP

# # DELETE
# export OS_TENANT_NAME=${PROJECT_NAME}
# nova delete ${PROJECT_NAME}-node

# neutron floatingip-delete $(neutron floatingip-list | awk '/ $FIP /{print $2}')

# neutron router-interface-delete ${PROJECT_NAME}-router ${PROJECT_NAME}-subnet
# neutron router-gateway-clear ${PROJECT_NAME}-router public-net
# neutron router-delete ${PROJECT_NAME}-router
# neutron net-delete ${PROJECT_NAME}-net

# nova secgroup-delete-rule default tcp 22 22 0.0.0.0/0
# nova secgroup-delete-rule default icmp -1 -1 0.0.0.0/0

# keystone tenant-delete ${PROJECT_NAME}
# source /root/.keystonerc
