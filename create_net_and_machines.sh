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


dhcpagent=a3edfcfa-c91b-4e24-98d0-51b79d1ee38d


extnet=`neutron net-show "public" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`

if neutron net-show "$tenant"-net 2>&1 | fgrep -q "Unable to find network"; then
 neutron net-create --vlan-transparent=True "$tenant"-net
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

if neutron net-show "${tenant}-net" 2>&1 | fgrep -q "Unable to find network"; then
  neutron net-create  "${tenant}-net"
fi

if neutron subnet-show "${tenant}-subnet" 2>&1 | fgrep -q "Unable to find subnet"; then
  neutron subnet-create --name "${tenant}-subnet" "${tenant}-net" 172.25.8.0/22 --gateway 172.25.8.1
fi

sid=`neutron subnet-show "${tenant}-subnet" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`
nid=`neutron net-show "${tenant}-net" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`


if [ x = "x$sid" -o x = "x$rid" -o x = "x$nid"  ]; then
    echo "Subnet, network or router issues for $proj, skipping."
else
    neutron router-interface-add "$rid" "$sid"
fi

neutron dhcp-agent-network-add "$dhcpagent" "${tenant}-net"

#

nova keypair-add --pub-key "$HOME"/.ssh/id_rsa.pub "$tenant"-key

neutron security-group-create "$tenant"-sg
neutron security-group-rule-create "$tenant"-sg --direction ingress --ethertype ipv4 --protocol icmp 
neutron security-group-rule-create "$tenant"-sg --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 22 --port-range-max 22
neutron security-group-rule-create "$tenant"-sg --direction ingress --ethertype ipv4 --protocol tcp --port-range-min 443 --port-range-max 443





nova boot --flavor m1.small --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.3 --key-name "$tenant"-key --security-group "$tenant"-sg filsluss
nova boot --flavor m1.small --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.4 --key-name "$tenant"-key --security-group "$tenant"-sg thinlinc-master
nova boot --flavor m1.small --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.5 --key-name "$tenant"-key --security-group "$tenant"-sg openstack-controller
nova boot --flavor m1.small --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.6 --key-name "$tenant"-key --security-group "$tenant"-sg supernode
nova boot --flavor m1.large --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.7 --key-name "$tenant"-key --security-group "$tenant"-sg compute1
nova boot --flavor m1.large --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.8 --key-name "$tenant"-key --security-group "$tenant"-sg compute2
nova boot --flavor m1.large --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.9 --key-name "$tenant"-key --security-group "$tenant"-sg compute3
nova boot --flavor m1.small --image CentOS6 --nic net-id="$nid",v4-fixed-ip=172.25.8.10 --key-name "$tenant"-key --security-group "$tenant"-sg hnas-emulation



nova floating-ip-associate filsluss "$ipprefix""$baseip"
nova floating-ip-associate thinlinc-master "$ipprefix""$((baseip+1))"
nova floating-ip-associate openstack-controller "$ipprefix""$((baseip+2))"
nova floating-ip-associate supernode "$ipprefix""$((baseip+3))"
nova floating-ip-associate compute1 "$ipprefix""$((baseip+4))"
nova floating-ip-associate compute2 "$ipprefix""$((baseip+5))"
nova floating-ip-associate compute3 "$ipprefix""$((baseip+6))"
nova floating-ip-associate hnas-emulation "$ipprefix""$((baseip+7))"


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
                                                                                  
[filsluss]
$ipprefix$((baseip))     

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

sleep 60
# Here because in cleanup we don't care about IPs (we don't care enough to pick up the information)
for p in {0..10}; do 
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$ipprefix""$((baseip+p))"
  ssh -oStrictHostKeyChecking=no "$ipprefix""$((baseip+p))"
done
