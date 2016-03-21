#!/bin/bash

if [ x"$1" = x ]; then
tenant=mmosler1
else
tenant="$1"
fi

if [ x"$2" = x ]; then
ipprefix=10.254.0.
else
ipprefix="$2"
fi

if [ x"$3" = x ]; then
baseip=51
else
baseip="$3"
fi


# Get credentials
. ~/"$tenant"-openrc.sh


for p in 1 2 3; do
  ./cleanup.sh
done

dhcpagent=a3edfcfa-c91b-4e24-98d0-51b79d1ee38d


extnet=`neutron net-show "public" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`

if neutron net-show "$tenant"-data-net 2>&1 | fgrep -q "Unable to find network"; then
 neutron net-create --vlan-transparent=True "$tenant"-data-net
fi

if neutron router-show "${tenant}-router" 2>&1 | fgrep -q "Unable to find router"; then
  neutron router-create  "${tenant}-router"
fi

rid=`neutron router-show "${tenant}-router"| sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`
      
if [ x = "x$rid" ]; then
    echo "Router issues for $proj, skipping."
else
    neutron router-gateway-set "$rid" "$extnet"
fi

if neutron net-show "${tenant}-mgmt-net" 2>&1 | fgrep -q "Unable to find network"; then
  neutron net-create  "${tenant}-mgmt-net"
fi

if neutron subnet-show "${tenant}-mgmt-subnet" 2>&1 | fgrep -q "Unable to find subnet"; then
  neutron subnet-create --name "${tenant}-mgmt-subnet" "${tenant}-mgmt-net" 172.25.8.0/22 --gateway 172.25.8.1
fi

if neutron net-show "${tenant}-data-net" 2>&1 | fgrep -q "Unable to find network"; then
  neutron net-create  "${tenant}-data-net"
fi

if neutron subnet-show "${tenant}-data-subnet" 2>&1 | fgrep -q "Unable to find subnet"; then
  neutron subnet-create --name "${tenant}-data-subnet" "${tenant}-data-net" 10.10.10.0/24 
fi

msid=`neutron subnet-show "${tenant}-mgmt-subnet" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`
mnid=`neutron net-show "${tenant}-mgmt-net" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`

dsid=`neutron subnet-show "${tenant}-data-subnet" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`
dnid=`neutron net-show "${tenant}-data-net" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`


if [ x = "x$msid" -o x = "x$rid" -o x = "x$mnid"  ]; then
    echo "Subnet, network or router issues for $proj, skipping."
else
    neutron router-interface-add "$rid" "$msid"
fi

neutron dhcp-agent-network-add "$dhcpagent" "${tenant}-mgmt-net"

#

nova keypair-add --pub-key "$HOME"/.ssh/id_rsa.pub "$tenant"-key

neutron security-group-create "$tenant"-sg
neutron security-group-rule-create "$tenant"-sg --direction ingress --ethertype ipv4 --protocol icmp 
neutron security-group-rule-create "$tenant"-sg --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 22 --port-range-max 22
neutron security-group-rule-create "$tenant"-sg --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 443 --port-range-max 443
neutron security-group-rule-create mmosler1-sg --ethertype ipv4 --direction ingress --remote-group-id mmosler1-sg
neutron security-group-rule-create mmosler1-sg --ethertype ipv4 --direction egress --remote-group-id mmosler1-sg





nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.3 --key-name "$tenant"-key --security-group "$tenant"-sg openstack-controller
nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.4 --key-name "$tenant"-key --security-group "$tenant"-sg thinlinc-master
nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.5 --key-name "$tenant"-key --security-group "$tenant"-sg filsluss
nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.6 --key-name "$tenant"-key --security-group "$tenant"-sg supernode
nova boot --flavor m1.large --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.7 --key-name "$tenant"-key --security-group "$tenant"-sg compute1
nova boot --flavor m1.large --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.8 --nic net-id="$dnid",v4-fixed-ip=10.10.10.111 --key-name "$tenant"-key --security-group "$tenant"-sg compute2
nova boot --flavor m1.large --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.9 --nic net-id="$dnid",v4-fixed-ip=10.10.10.112 --key-name "$tenant"-key --security-group "$tenant"-sg compute3
nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.10 --key-name "$tenant"-key --security-group "$tenant"-sg hnas-emulation
nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.11 --key-name "$tenant"-key --security-group "$tenant"-sg ldap
nova boot --flavor m1.small --image CentOS6 --nic net-id="$mnid",v4-fixed-ip=172.25.8.12 --nic net-id="$dnid",v4-fixed-ip=10.10.10.101 --key-name "$tenant"-key --security-group "$tenant"-sg networking-node



nova floating-ip-associate filsluss "$ipprefix""$baseip"
nova floating-ip-associate thinlinc-master "$ipprefix""$((baseip+1))"
nova floating-ip-associate openstack-controller "$ipprefix""$((baseip+2))"
nova floating-ip-associate supernode "$ipprefix""$((baseip+3))"
nova floating-ip-associate compute1 "$ipprefix""$((baseip+4))"
nova floating-ip-associate compute2 "$ipprefix""$((baseip+5))"
nova floating-ip-associate compute3 "$ipprefix""$((baseip+6))"
nova floating-ip-associate hnas-emulation "$ipprefix""$((baseip+7))"
nova floating-ip-associate ldap "$ipprefix""$((baseip+8))"
nova floating-ip-associate networking-node "$ipprefix""$((baseip+9))"


cat - > /tmp/inventory-"$tenant" <<EOF
[all]
$ipprefix$((baseip))     
$ipprefix$((baseip+1))     
$ipprefix$((baseip+2))     
$ipprefix$((baseip+3))     
$ipprefix$((baseip+4))     
$ipprefix$((baseip+5))     
$ipprefix$((baseip+6))     
$ipprefix$((baseip+7))     
$ipprefix$((baseip+8))     
$ipprefix$((baseip+9))     
                                                                                  
[filsluss]
$ipprefix$((baseip))     

[networking-node]
$ipprefix$((baseip+9))     

[ldap]
$ipprefix$((baseip+8))     

[thinlinc-master]
$ipprefix$((baseip+1))     

[openstack-controller]
$ipprefix$((baseip+2))     

[supernode]
$ipprefix$((baseip+3))     

[compute]
$ipprefix$((baseip+4))
$ipprefix$((baseip+5))
$ipprefix$((baseip+6))

[hnas-emulation]
$ipprefix$((baseip+7))


EOF

# Wait for all hosts
while true; do
  for p in {0..9}; do
    ssh -oStrictHostKeyChecking=no -tt centos@"$ipprefix""$((baseip+p))" echo finished 
  done | grep -c finished | grep -q 10 && break
done


# Here because in cleanup we don't care about IPs (we don't care enough to pick up the information)
for p in {0..9}; do 
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$ipprefix""$((baseip+p))"
  
  ssh -oStrictHostKeyChecking=no -tt centos@"$ipprefix""$((baseip+p))" 'echo proxy=http://130.238.7.178:3128/ | sudo tee -a /etc/yum.conf' </dev/null
  ssh -oStrictHostKeyChecking=no -tt centos@"$ipprefix""$((baseip+p))"  'sudo yum -y install epel-release'  < /dev/null
 ssh -oStrictHostKeyChecking=no -tt centos@"$ipprefix""$((baseip+p))"  'sudo yum -y install cloud-utils-growpart && sudo growpart /dev/vda 1 && sudo shutdown -r now'  < /dev/null
done

# Wait for all hosts
while true; do
  for p in {0..9}; do
    ssh -oStrictHostKeyChecking=no -tt centos@"$ipprefix""$((baseip+p))" echo finished 
  done | grep -c finished | grep -q 10 && break
done



# We want to set up right away.

ansible-playbook -u centos -i /tmp/inventory-"$tenant" $HOME/mosler-micro-mosler/playbooks/micromosler.yml

