# Knox - ePouta

This set of scripts allows you to create and set up virtual machines
(VMs) in an Openstack cluster. Some VMs will be booted on
the [Knox cluster](http://knox.bils.se/horizon) (in Sweden) and some
others on the [ePouta cloud](https://research.csc.fi/epouta) (in
Finland).  This created set of virtual machines will be the base for
testing the connection between Knox and ePouta.

You can have a look at
an
[informal presentation](https://nbisweden.github.io/Knox-ePouta/informal) or
a
[more technical presentation](https://nbisweden.github.io/Knox-ePouta/).

## Requirements
You first need to create a few files with the different cloud
credentials. Copy the files `lib/settings/<cloud>.rc.sample` into
`lib/settings/<cloud>.rc` and edit the relevant parameters. This will
often boil down to updating:

	export OS_TENANT_NAME=<tenant-name>
	export OS_TENANT_ID=<tenant-id>
	export OS_USERNAME=<username>
	export OS_PASSWORD=<password>

These settings will probably be given to you by your _openstack
administrator_. Note that this user might need an admin role for the
given tenant/project. This is the case for Knox, since we also provide
scripts to set up the network infrastructure.

The scripts define some variables (in `lib/settings/common.rc`)
* `KE_HOME` (that current folder)
* `BIO_DATA` (currently pointing to `/home/fred/BioInfo/data`)
* `BIO_SW` (currently pointing to `/home/fred/BioInfo/sw`)

The scripts will try to use a CentOS7 glance image (Read: make sure it
is installed), or even better: it can use a custom build image of your
choosing (already uploaded to Glance).

Edit the file `lib/settings/common.rc` if you are interested in
updating settings such as VMs IP address, network CIDR, etc...

## Execution

These scripts are build to run on Knox.

Prior to creating the VMs, whether on Knox or ePouta, it is necessary
to make sure the necessary network components are set up.  On ePouta,
it was already done. On Knox, you can have a look at the script
`lib/knox-net.sh` which creates the necessary routers, networks and
security groups.

Once the network settings are in place (on Knox), two linux network
namespaces are available: one for the virtual router (starting with
`qrouter`) and one for the project's DHCP server (starting with
`qdhcp`).

	[controller]$ ip netns
	qrouter-2b34b042-afaa-485c-86ae-9afa6e7d494f
	qdhcp-8060ed02-cba7-4f2a-a8c5-e0ee5c238556


All the commands are run inside the namespace of the Virtual
Router. In order to _go into that namespace_, we issue the following
command. Note that the `-E` allows the environment variables to follow
with us, in particular the `SSH_AUTH_SOCK`, so that we can still use
the ssh keys that were preloaded in the ssh agent.

	sudo -E ip netns exec qrouter-2b34b042-afaa-485c-86ae-9afa6e7d494f bash
	
A few routes must be added to the virtual router, in order to give the
VMs an external access. It is simpler to add a route to a DNS
server. Moreover, in our case, we did not give a full access to
internet. We rather added a route to one of Uppsala University's
proxies. (Note: the `gw` interface is the _way out from the router_)

	[virtual-router]# ip route show
	10.5.0.0/24 dev gw  proto kernel  scope link  src 10.5.0.2 
	10.101.0.0/16 dev qr-<some-id>  proto kernel  scope link  src 10.101.0.1 
	<knox-controller-IP> via 10.5.0.1 dev gw 
	<DNS-server-IP> via 10.5.0.1 dev gw 
	<proxy-server-IP> via 10.5.0.1 dev gw 

Once the network components are set up, we can use the following
commands, provided here only for convenience.

* `knox-epouta init <cloud>` allows you to create the VMs related to
`<cloud>`. In particular here, `supernode, storage, knox{1..3}` will
be booted on Knox and `epouta{1..3}` will be booted on ePouta. There
are different parameters you can tweak: Append the `-h` flag to see
their description.
* `knox-epouta sync` copies the required files to the appropriate
servers (along with installing the required packages).
* `knox-epouta provision` runs the different profiles for each
VM. This configures the servers. The task should be idempotent.
* `knox-epouta reset` erases what the provisioning phase did.

You can append the `-q` flag to turn off the verbose output.
You can append the `-h` flag to see the command options.

Finally, use `knox-epouta connect <machine>` (from the router) to log
onto the mentioned VM. The `supernode` VM was created so that we'd run
any command from it. It is, for example, the `slurm controller` and
the place where test-scripts are located and the results are stored.

## Example

	git clone https://github.com/NBISweden/Knox-ePouta <some_dir>
	cd <that_dir>/experiments/
	
	cp lib/settings/knox.rc.sample lib/settings/knox.rc
	sed -i -e '/OS_TENANT_NAME=*/OS_TENANT_NAME=vanilla/' lib/settings/knox.rc
	sed -i -e '/OS_TENANT_ID=*/OS_TENANT_ID=<some-id>/' lib/settings/knox.rc
	sed -i -e '/OS_USERNAME=*/OS_USERNAME=fred/' lib/settings/knox.rc
	sed -i -e '/OS_PASSWORD=*/OS_PASSWORD=holala/' lib/settings/knox.rc
	
	./knox-epouta init knox --image CentOS7-extended
	./knox-epouta init epouta --image CentOS7-extended
	./knox-epouta sync
	./knox-epouta provision
	
	./knox-epouta connect supernode
	/usr/local/bin/run-CAW.sh
	/usr/local/bin/run-WGS.sh
	# etc...


