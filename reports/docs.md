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

Updating the network on ePouta:

	fred@knox1:~$ neutron subnet-show UU-MOSLER-subnet
	+-------------------+--------------------------------------------------+
	| Field             | Value                                            |
	+-------------------+--------------------------------------------------+
	| allocation_pools  | {"start": "10.101.0.2", "end": "10.101.127.255"} |
	| cidr              | 10.101.0.0/16                                    |
	| dns_nameservers   | 10.101.128.2                                     |
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



	[virtual-router] # iptables -t nat -S
	...
	-A POSTROUTING -o gw -j SNAT --to-source 10.5.0.2
	...



# Preparing the network

The following commands create a network namespace, a bridge, and a
veth pair that is dedicated for the 10.101.0.0/16 network.

	# Create a router (Note its ID)
	neutron router-create ${OS_TENANT_NAME}-mgmt-router
	# Create a network (on VLAN 1203)
	neutron net-create --provider:network_type vlan --provider:physical_network vlan --provider:segmentation_id 1203 ${OS_TENANT_NAME}-mgmt-net
	# neutron subnet-create --name ${OS_TENANT_NAME}-mgmt-subnet ${OS_TENANT_NAME}-mgmt-net --allocation-pool start=10.101.128.1,end=10.101.255.254 --gateway 10.101.0.1 10.101.0.0/16
	# Add an interface in the router for that 101 network
	neutron router-interface-add ${OS_TENANT_NAME}-mgmt-router ${OS_TENANT_NAME}-mgmt-subnet
	

We think we found a problem with MAC address on the bridge in
Ubuntu. A quickfix is to disable the MAC learning algorithm of the
bridge, and make it behave like a hub (and not a virtual switch). We
don't recall that it was necessary on CentOS.

	brctl setageing brq<...>  0 

We then create the necessary interfaces in order to get external
access to the router, though limited.

	# Create a veth pair for external access to the virtual router
	ip link add gw type veth peer name mm
	# Add the gw interface to the virtual router
	ip link set gw netns qrouter-<...>
	# Give an ip to `mm`
	ip addr add 10.5.0.1/24 dev mm

Inside the Virtual router:

	# Give an ip to `gw`, and bring it up (that'll bring `mm` up on the other side too)
	[virtual-router] # ip addr add 10.5.0.2/24 dev gw
	                 # ip link set dev gw up

The routes in the Virtual Router are so far:

	[virtual-router] # ip route show
	10.5.0.0/24 dev gw  proto kernel  scope link  src 10.5.0.2 
	10.101.0.0/16 dev qr-<...>  scope link  src 10.101.0.1 

We add a few other ones:

	[virtual-router] # ip route add 10.254.0.1/32 via 10.5.0.1 dev gw    # Knox openstack endpoint
	                 # ip route add 86.50.28.63/32 via 10.5.0.1 dev gw   # ePouta openstack endpoint
	                 # ip route add 130.238.7.10/32 via 10.5.0.1 dev gw  # UU DNS
	                 # ip route add 130.238.7.178/32 via 10.5.0.1 dev gw # UU proxy


Finally, 

	[virtual-router] # ip addr list
	1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default 
		link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
		inet 127.0.0.1/8 scope host lo
		valid_lft forever preferred_lft forever
	2: qr-<...>: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
		link/ether fa:16:3e:44:18:8f brd ff:ff:ff:ff:ff:ff
		inet 10.101.0.1/16 brd 10.101.255.255 scope global qr-bec87232-23
		valid_lft forever preferred_lft forever
	40: gw: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
		link/ether 36:66:d6:4f:d5:d1 brd ff:ff:ff:ff:ff:ff
		inet 10.5.0.2/24 scope global gw
		valid_lft forever preferred_lft forever

	[virtual-router] # ip route show
	10.5.0.0/24 dev gw  proto kernel  scope link  src 10.5.0.2 
	10.101.0.0/16 dev qr-<...>  proto kernel  scope link  src 10.101.0.1 
	10.254.0.1 via 10.5.0.1 dev gw 
	86.50.28.63 via 10.5.0.1 dev gw 
	130.238.7.10 via 10.5.0.1 dev gw 
	130.238.7.178 via 10.5.0.1 dev gw 




# For Leif

We gave an IP on the 10.101.0.0/16 network and adjusted the routes so that this network is routed through
the created bridge

	[controller] $ ip addr add 10.101.127.254/16 dev brq<...>
	brq<...>: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 0e:d5:71:c6:a5:da brd ff:ff:ff:ff:ff:ff
    inet 10.101.127.254/16 scope global brq<...>
       valid_lft forever preferred_lft forever
	   
	[controller] $ ip route show
	...
	10.101.0.0/16 dev brq<...>  proto kernel scope link src 10.101.127.254
	...
	

# Notes

* MAC/IP filtering on the bridges. did byte us in the...
* Broadcast traffic is still forwarded to all interface on VLAN 1203
  and therefore to all VMs. An improvment would be to use OpenVSwitch
  to learn about MAC addresses and skip physical nodes that don't host
  any VMs on that project. That will improve East-West traffic. An
  alternative is to distribute the router using DVR (not available
  when using the Linux Bridge mechanism).


