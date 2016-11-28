# Knox setup for the Epouta connection

This document describes how we connected a set of virtual machines
(VMs) running on Knox, in Sweden, to another set of VMs running on
ePouta, in Finland.

We start with the low-level component. There is a 1GB/s fiber-link
between Knox and ePouta with a dedicated network. This means that the
link might be shared, but only the VMs on that network can communicate
through it. This security is provided by VLAN encapsulation. In our
case, the VLAN tag is 1203.

The network will use the following range of IPs: `10.101.0.0/16`.

The network settings use the following components:
* a Virtual Router on Knox (with IP: 10.101.0.1/16)
* a DHCP server on Knox (with IP: 10.101.128.2/16)
* a DHCP server on ePouta (with IP: 10.101.0.3/16)
* the Neutron Openstack linuxbridges plugin (on Knox) with VLAN capabilities

and of course 
* a set of VMs on ePouta (with IP: 10.101.0.4/16 to 10.101.127.255/16)<br/>...that is, the third number starts in binary notation with a 0.
* a set of VMs on Knox (with IP: 10.101.128.3/16 to 10.101.128.254/16)<br/>...that is, the third number starts in binary notation with a 1.

## The Virtual Router and DHCP server, on Knox

Openstack uses the network namespace capabilities of the Linux kernel,
in order to isolate routes, firewall rules and interfaces from the
root namespace. This is where the virtual router and the dhcp server
live, each in its own namespace. 


	[controller]$ ip netns
	qrouter-<some-uuid>
	qdhcp-<some-other-uuid>

The neutron plugin creates veth pairs, where one end is moved to a
network namespace, and the other end is still in the root namespace.
The end in the router namespace is of the form `qr-<some-uuid>` and
the one in the dhcp namespace is of the form `ns-<some-uuid>` (This
naming is for historical reasons, in the early stages of the neutron
project).

The other end of the veth pairs, in the root namespace, is added to a
linux bridge. Openstack creates a linux bridge per project.

Moreover, the plugin makes sure that the outgoing interface, of the
physical host, uses the VLAN tag 1203, and is also added to that same
bridge, therefore providing connectivity and security to the router
(over that VLAN).

![neutron on controller](./img/controller.jpeg)

The dhcp namespace isolates a `dnsmasq` process, while the other
namespace isolates routes and IPtables rules for the virtual router.

## VM connectivity on the compute nodes

On each compute node, a bridge is created (also per project), along
with an interface with VLAN tag 1203. A veth pair's end is added to
the bridge, while to other end is used by a VM, as its internal
interface.

A kernel setting is used to force `IPtables` to filter traffic on the
bridge. This is the way Openstack enforces security groups and in
particular ensures some address spoofing protections. We'll come back
to it later.

![neutron on compute node](./img/compute-node.jpeg)


## External connectivity for the VMs

All VMs have a default route to the virtual router. Therefore,
external connectivity is adjusted in the virtual router's namespace.

Openstack usually creates a veth pair, where one end is a `gateway`
interface added to the virtual router, and the router translates the
source address (source NATing, SNAT), using IPTables, for outgoing
traffic over that interface. Traffic to the 10.101.0.0/16 network is
routed through the `qr-<some-id>` interface, and all other traffic is
routed through the gateway interface.

The other end of the veth pair is still in the root namespace, and is
added to an _external_ bridge, which already forwards traffic to the
host's external interface.  That way, all virtual routers have
external connectivity.

However, in our case, we did not need all those settings, so we only
used one veth pair (called `gw <-> mm`), along with a fake external
network `10.5.0.0/24`.


----


<p style="text-align: center; font-size: 3em; border:1px solid red;">
SO FAR SO GOOD
</p>


----



The router does not have any connection outside the `101` network. The
exception is the address 130.238.7.178 which is the UU proxy. Each
bridge is linked to a VLAN interface. 


	[controller] $ ip addr show dev mm
	41: mm: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether aa:92:cb:e8:a4:d2 brd ff:ff:ff:ff:ff:ff
    inet 10.5.0.1/24 scope global mm
       valid_lft forever preferred_lft forever

	[controller] $ ip route show
	10.5.0.0/24 dev mm proto kernel scope link src 10.5.0.1

	[virtual-router] # iptables -t nat -A POSTROUTING -o gw -j SNAT --to-source 10.5.0.2

Our `FORWARD` chain in IPTables has a DROP policy
(i.e. it defaults to dropping all packets in case no chain accepted
them), so we had to adjust the chain to allow traffic to flow to the
`mm` interface.

	[controller] # iptables -S FORWARD
	-P FORWARD DROP
	-A FORWARD ! -i <external-interface> -j ACCEPT

We chose to not give a full external connectivity to the VMs. We do
not have a default route in the routing table of the virtual
router. We only added one to one of Uppsala University's proxy 130.238.7.178.

	[virtual-router] # ip route show
	10.5.0.0/24 dev gw  proto kernel  scope link  src 10.5.0.2 
	10.101.0.0/16 dev qr-<id> proto kernel  scope link  src 10.101.0.1 
	130.238.7.178 via 10.5.0.1 dev gw 




Security rules are implemented on each compute node, as IPtable rules
filtering the bridge traffic. These rules are added by Openstack and
can be slightly manipulated by updating the neutron port settings.

	[compute-node] $ brctl show
	bridge name	    bridge id		    STP enabled	interfaces
	brq8060ed02-cb	8000.ecb1d7830cb0	no		      em1.1203
	                                            tapb83935a5-30
												tapeeec86c0-83


	[compute-node] # iptables -S FORWARD
	-A FORWARD -j neutron-linuxbri-FORWARD

	[compute-node] # iptables -S neutron-linuxbri-FORWARD
	-A neutron-linuxbri-FORWARD -m physdev --physdev-out tapb83935a5-30 --physdev-is-bridged -m comment --comment "Direct traffic from the VM interface to the security group chain." -j neutron-linuxbri-sg-chain
	-A neutron-linuxbri-FORWARD -m physdev --physdev-in tapb83935a5-30 --physdev-is-bridged -m comment --comment "Direct traffic from the VM interface to the security group chain." -j neutron-linuxbri-sg-chain
	...

	[compute-node] # iptables -S neutron-linuxbri-sg-chain
	-N neutron-linuxbri-sg-chain
	-A neutron-linuxbri-sg-chain -m physdev --physdev-out tapb83935a5-30 --physdev-is-bridged -m comment --comment "Jump to the VM specific chain." -j neutron-linuxbri-ib83935a5-3
	-A neutron-linuxbri-sg-chain -m physdev --physdev-in tapb83935a5-30 --physdev-is-bridged -m comment --comment "Jump to the VM specific chain." -j neutron-linuxbri-ob83935a5-3
	-A neutron-linuxbri-sg-chain -j ACCEPT


	[compute-node] # iptables -S neutron-linuxbri-ob83935a5-3
	-N neutron-linuxbri-ob83935a5-3
	-A neutron-linuxbri-ob83935a5-3 -p udp -m udp --sport 68 -m udp --dport 67 -m comment --comment "Allow DHCP client traffic." -j RETURN
	-A neutron-linuxbri-ob83935a5-3 -j neutron-linuxbri-sb83935a5-3
	-A neutron-linuxbri-ob83935a5-3 -p udp -m udp --sport 67 -m udp --dport 68 -m comment --comment "Prevent DHCP Spoofing by VM." -j DROP
	-A neutron-linuxbri-ob83935a5-3 -m state --state RELATED,ESTABLISHED -m comment --comment "Direct packets associated with a known session to the RETURN chain." -j RETURN
	-A neutron-linuxbri-ob83935a5-3 -j RETURN
	-A neutron-linuxbri-ob83935a5-3 -m state --state INVALID -m comment --comment "Drop packets that appear related to an existing connection (e.g. TCP ACK/FIN) but do not have an entry in conntrack." -j DROP
	-A neutron-linuxbri-ob83935a5-3 -m comment --comment "Send unmatched traffic to the fallback chain." -j neutron-linuxbri-sg-fallback


	[compute-node] # iptables -S neutron-linuxbri-ib83935a5-3
	-N neutron-linuxbri-ib83935a5-3
	-A neutron-linuxbri-ib83935a5-3 -m state --state RELATED,ESTABLISHED -m comment --comment "Direct packets associated with a known session to the RETURN chain." -j RETURN
	-A neutron-linuxbri-ib83935a5-3 -s 10.101.128.2/32 -p udp -m udp --sport 67 -m udp --dport 68 -j RETURN
	-A neutron-linuxbri-ib83935a5-3 -s 10.101.0.0/16 -p icmp -j RETURN
	-A neutron-linuxbri-ib83935a5-3 -s 10.101.0.0/16 -p tcp -m tcp -m multiport --dports 1:65535 -j RETURN
	-A neutron-linuxbri-ib83935a5-3 -m set --match-set NIPv4ef2c878c-caf7-4c69-b6a5- src -j RETURN
	-A neutron-linuxbri-ib83935a5-3 -m state --state INVALID -m comment --comment "Drop packets that appear related to an existing connection (e.g. TCP ACK/FIN) but do not have an entry in conntrack." -j DROP
	-A neutron-linuxbri-ib83935a5-3 -m comment --comment "Send unmatched traffic to the fallback chain." -j neutron-linuxbri-sg-fallback

	[compute-node] # iptables -S neutron-linuxbri-sb83935a5-3
	-N neutron-linuxbri-sb83935a5-3
	-A neutron-linuxbri-sb83935a5-3 -s 10.101.128.100/32 -m mac --mac-source FA:16:3E:8B:C4:6A -m comment --comment "Allow traffic from defined IP/MAC pairs." -j RETURN
	-A neutron-linuxbri-sb83935a5-3 -m comment --comment "Drop traffic without an IP/MAC allow rule." -j DROP
	
	[compute-node] # iptables -S neutron-linuxbri-sg-fallback
	-N neutron-linuxbri-sg-fallback
	-A neutron-linuxbri-sg-fallback -m comment --comment "Default drop rule for unmatched traffic." -j DROP

	[compute-node] # ipset list NIPv4ef2c878c-caf7-4c69-b6a5-
	Name: NIPv4ef2c878c-caf7-4c69-b6a5-
	Type: hash:net
	Revision: 4
	Header: family inet hashsize 1024 maxelem 65536
	Size in memory: 16920
	References: 2
	Members:
	10.101.128.100
	10.101.128.102
	10.101.128.104
	10.101.128.101
	10.101.128.103





* allowed MAC/IP or filtering by iptables on the bridges of the compute nodes

# For Leif

	[controller] $ ip addr show dev brq8060ed02-cb
	brq8060ed02-cb: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 0e:d5:71:c6:a5:da brd ff:ff:ff:ff:ff:ff
    inet 10.101.0.2/16 scope global brq8060ed02-cb
       valid_lft forever preferred_lft forever
	   

	[controller] $ ip route show
	10.101.0.0/16 dev brq8060ed02-cb  scope link 

# Notes

* MAC/IP filtering on the bridges. did byte us in the...
* Bridge MAC address problem on Ubuntu. setageing to 0, making the
  bridge behave as a hub and not a virtual switch.
* Broadcast traffic is still forwarded to all interface on VLAN 1203
  and therefore to all VMs. An improvment would be to use OpenVSwitch
  to learn about MAC addresses and skip physical nodes that don't host
  any VMs on that project. That will improve East-West traffic. An
  alternative is to distribute the router using DVR (not available
  when using the Linux Bridge mechanism).


