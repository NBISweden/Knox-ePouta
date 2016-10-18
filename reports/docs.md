# Knox setup for the Epouta connection

This document describes how we set up a test project that runs on
Knox, and uses Epouta's virtual machines (VMs) to extend the list of
compute nodes.

There is a dedicated fiber link between Knox and Epouta.

Assume we have a project running in a (micro)mosler environment, and
that this project uses a set of VMs on Knox. We use Epouta's VMs to
extend the latter set.

In reality, we do not have a mosler setup. Instead, we use a vanilla
openstack installation, and non-sensitive data (or rather, trivial
data from a small test case). On this openstack installation, we
instantiate a project on VLAN 1203. The VMs on that VLAN will be
communicate transparently to the ones in Epouta.

Connectivity between the VMs is ensured by the Linux Bridge plugin in
Neutron, and we use the VLAN capabilities of that plugin. We
illustrate how the network looks like on the controller node.

![neutron](http://docs.openstack.org/liberty/networking-guide/_images/scenario-legacy-lb-network2.png)

And on the compute node:
![neutron-compute](http://docs.openstack.org/liberty/networking-guide/_images/scenario-legacy-lb-compute2.png)

* IP routes
* Iptables rules for FORWARD (from em4 into the others)
* Security rules
* allowed MAC/IP or filtering by iptables on the bridges of the compute nodes

# Things that did byte us in the...

MAC/IP filtering on the bridges.
