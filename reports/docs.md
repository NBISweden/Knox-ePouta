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
* a DHCP server on Knox (with IP: 10.101.128.0/16)
* a DHCP server on ePouta (with IP: 10.101.0.3/16)
* the Neutron Openstack linuxbridges plugin (on Knox) with VLAN capabilities

and of course 
* a set of VMs on ePouta (with IP: 10.101.0.4/16 to 10.101.127.255/16)<br/>...that is, the third number starts in binary notation with a 0.
* a set of VMs on Knox (with IP: 10.101.128.1/16 to 10.101.128.254/16)<br/>...that is, the third number starts in binary notation with a 1.

# Adjusting the network on ePouta

We split the `10.101.0.0/16` address range in two disjoint parts. For
that, we use the third number of the latter CIDR. The VMs in ePouta
will have an IP where the third number starts in binary notation with
a 0, while, for the VMs in Knox, the third number will start with a
`1`. In other words, the IPs for the VMs in ePouta range from
`10.101.0.4` to `10.101.127.255`, while the ones in Knox, range from
`10.101.128.1` to `10.101.128.254`. The DHCP server for the VMs on
Knox is at IP `10.101.128.0` and we already know that the virtual
router is at `10.101.0.1`. Note that there is a DHCP server in ePouta
for the ePouta VMs at `10.101.0.3`.

It is necessary to adjust the network settings in ePouta accordingly.

	[controller]$ source <ePouta.credentials>
	
	[controller]$ neutron subnet-update UU-MOSLER-subnet \
	                      --allocation-pools type=dict list=true
	                      start=10.101.0.2,end=10.101.127.255 \
	                      --dns-nameserver 10.101.128.0
	
	[controller]$ neutron subnet-show UU-MOSLER-subnet
	+-------------------+--------------------------------------------------+
	| Field             | Value                                            |
	+-------------------+--------------------------------------------------+
	| allocation_pools  | {"start": "10.101.0.2", "end": "10.101.127.255"} |
	| cidr              | 10.101.0.0/16                                    |
	| dns_nameservers   | 10.101.128.0                                     |
	| enable_dhcp       | True                                             |
	| gateway_ip        | 10.101.0.1                                       |
	| host_routes       |                                                  |
	| id                | ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj             |
	| ip_version        | 4                                                |
	| name              | UU-MOSLER-subnet                                 |
	| network_id        | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee             |
	| subnetpool_id     |                                                  |
	| tenant_id         | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa                 |
	+-------------------+--------------------------------------------------+


# The Virtual Router and DHCP server, <i>on Knox</i>

Openstack uses the network namespace capabilities of the Linux kernel,
in order to isolate routes, firewall rules and interfaces from the
root namespace. This is where the virtual router and the dhcp server
live, each in its own namespace. Note that we are
using
[Openstack Liberty](http://docs.openstack.org/liberty/install-guide-ubuntu/) on
Knox, and that the naming convention is such that network components
(often) start with `q`. This is for historical reasons: _Neutron_ used
to be called _Quantum_.


	[controller]$ ip netns
	qrouter-<some-uuid>
	qdhcp-<some-other-uuid>

The neutron plugin creates veth pairs, where one end is moved to a
network namespace, and the other end is still in the root namespace.
The end in the router namespace is of the form `qr-<some-uuid>` and
the one in the dhcp namespace is of the form `ns-<some-uuid>`. The
other end of the veth pairs, in the root namespace, is added to a
linux bridge. Openstack creates a linux bridge per project.

Moreover, the plugin makes sure that the outgoing interface, of the
physical host, uses the VLAN tag 1203, and is also added to that same
bridge, therefore providing connectivity and security to the router
(over that VLAN).

The dhcp namespace isolates a `dnsmasq` process, while the other
namespace isolates routes and IPtables rules for the virtual router.

![neutron on controller](./img/controller.jpeg)

The following openstack commands create the necessary underlying
components on the Knox `controller` for connecting the different VMs,
either in Knox or in ePouta, to the outside world. The components are
a network namespace, a bridge, and a veth pair that is dedicated for
the 10.101.0.0/16 network.

	# Create a router (Note its ID)
	neutron router-create ${OS_TENANT_NAME}-mgmt-router # This creates the above-mentioned qrouter-<...>
	
	# Create a network (on VLAN 1203)
	neutron net-create --provider:network_type vlan \
	                   --provider:physical_network vlan \
					   --provider:segmentation_id 1203 \
					   ${OS_TENANT_NAME}-mgmt-net
	
	# Specify the IP range
	neutron subnet-create --name ${OS_TENANT_NAME}-mgmt-subnet \
	                      --allocation-pool start=10.101.128.1,end=10.101.255.254 \
						  --gateway 10.101.0.1 \
						  ${OS_TENANT_NAME}-mgmt-net 10.101.0.0/16
	
	# Add an interface in the router for that 101 network
	neutron router-interface-add ${OS_TENANT_NAME}-mgmt-router ${OS_TENANT_NAME}-mgmt-subnet
	
	# At this stage, the above-mentioned qdhcp-<...> is created.
	

We think we found a problem with MAC addresses on the linux bridge in
Ubuntu: The tap interface connected to the virtual router is learned
on the wrong port of the bridge. Moreover, the MAC address of the
bridge itself is by construction to lowest one of all its interfaces,
unless its MAC address is fixed at creation. Updating the openstack
plugin for fixing the bridge's MAC address was not a solution in
mind. Instead, we opted for the following quickfix: We disabled the
MAC learning algorithm of the bridge, and made it behave like a hub
(and not a virtual switch). We don't recall that it was necessary on
CentOS.

	brctl setageing brq<...>  0 


# External connectivity for the VMs

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


We then create the necessary interfaces in order to get external
access to the router, though limited. It is composed of a single veth
pair, denoted `mm <-> gw`, where `gw` belongs to the virtual router
and have an IP on a "local" 10.5.0.0/24 network.

	# Create a veth pair for external access to the virtual router
	ip link add gw type veth peer name mm
	
	# Add the gw interface to the virtual router
	ip link set gw netns qrouter-<...> # Fill in the Virtual Router's ID
	
	# Give an ip to `mm`
	ip addr add 10.5.0.1/24 dev mm

Inside the Virtual router:

	# Give an ip to `gw`, and bring it up
	[virtual-router] # ip addr add 10.5.0.2/24 dev gw
	                 # ip link set dev gw up # that'll bring `mm` up on the other side too

The routes in the Virtual Router are so far:

	[virtual-router] # ip route show
	10.5.0.0/24 dev gw  proto kernel  scope link  src 10.5.0.2 
	10.101.0.0/16 dev qr-<...>  scope link  src 10.101.0.1 

We chose to not give a full external connectivity to the VMs. We do
not have a `default` route in the routing table of the virtual
router. Instead, we only added a few extra routes as follows:

	[virtual-router] # ip route add 10.254.0.1/32 via 10.5.0.1 dev gw    # Knox openstack endpoint
	                 # ip route add 86.50.28.63/32 via 10.5.0.1 dev gw   # ePouta openstack endpoint
	                 # ip route add 130.238.7.10/32 via 10.5.0.1 dev gw  # UU DNS
	                 # ip route add 130.238.7.178/32 via 10.5.0.1 dev gw # UU proxy

Moreover, for external connectivity, it is necessary to _source NAT_ the
traffic coming out of the virtual router.

	[virtual-router] # iptables -t nat -S
	...
	-A POSTROUTING -o gw -j SNAT --to-source 10.5.0.2
	...

It is connected to the root namespace via 2 tap interfaces: the
external one we added by hand and the one openstack created for the
10.101.0.0/16 network (and vlan 1203).


	[controller] $ brctl show
	bridge name	    [...] STP enabled	 interfaces
	brq1a6abf7e-f9	[...] no             em1.1203       # for VLAN separation
	                                     tap5a9dea61-d4 # for the 10.101.0.0/16 router interface
	                                     tapaeffc08d-63 # for the dhcp namespace



# VM connectivity on the compute nodes

On each compute node, a bridge is created (also per project), along
with an interface with VLAN tag 1203. A veth pair's end is added to
the bridge, while to other end is used by a VM, as its internal
interface.

A kernel setting is used to force `IPtables` to filter traffic on the
bridge. This is the way Openstack enforces security groups and in
particular ensures some address spoofing protections. 

![neutron on compute node](./img/compute-node.jpeg)


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



# Notes

Broadcast traffic is still forwarded to all interfaces on VLAN 1203 and
therefore to all VMs. An improvment would be to use OpenVSwitch to
learn about MAC addresses and skip physical nodes that don't host any
VMs on that project. That will improve East-West traffic. An
alternative is to distribute the router using DVR (not available when
using the Linux Bridge mechanism).


