# Knox - ePouta

This set of scripts allows you to create and set up virtual machines
(VMs) in an Openstack cluster. Some VMs will be booted on
the [Knox cluster](http://knox.bils.se/horizon) and some others on
the [ePouta cloud](https://research.csc.fi/epouta).  This created set
of virtual machines will be the base for testing the connection
between Knox (in Sweden) and ePouta (in Finland).

You can have a look at
the [informal presentation](https://nbisweden.github.io/Knox-ePouta/).

These scripts are build to run on Knox.

## Requirements
You first need to create a file (named 'user.rc') in order to set up
your openstack credentials for both Knox and ePouta. That file will
contain 3 variables:

	export KNOX_TENANT_NAME=<tenant-name>
	export KNOX_USERNAME=<username>
	export KNOX_PASSWORD=<password>
	export EPOUTA_TENANT_NAME=<tenant-name>
	export EPOUTA_USERNAME=<username>
	export EPOUTA_PASSWORD=<password>

This user must have the admin role for the given tenant/project. These
settings will probably be given to you by your _openstack administrator_.

The scripts define some variables (in `lib/settings.sh`)
* `KE_HOME` (that current folder)
* `BIO_DATA` (currently pointing to `/home/fred/BioInfo/data`)
* `BIO_SW` (currently pointing to `/home/fred/BioInfo/sw`)

The scripts will try to use a CentOS7 glance image (Read: make sure it
is installed), or even better: it can use a custom build image of your
choosing (already uploaded to Glance).

The `lib/settings.sh` file contains all the relevant settings, such as
VMs IP address, network CIDR, etc...

## Execution

Prior to creating the VMs, whether on Knox or ePouta, it is necessary
to make sure the necessary network components are set up.  On ePouta,
it was already done. On Knox, you can run (once) `knox-epouta
create-net` in order to create the necessary routers, networks and
security groups.

In subsequent runs, `knox-epouta init` will only create the VMs,
assuming the network is set up.

Run `knox-epouta sync` in order to copy the required files to the
appropriate servers (along with installing the required packages).

Run `knox-epouta provision` in order to provision each VM. This
configures the servers. The task should be idempotent.

Run `knox-epouta reset` if you want to erase what the provisioning
phase did.

The `knox-epouta clean` only deletes the running VMs.

The `knox-epouta delete-net` command destroy routers, networks,
security groups and floating IPs.

You can append the `-q` flag to turn off the verbose output.
You can append the `-h` flag to see the command options.

## Example
	git clone https://github.com/NBISweden/Knox-ePouta <some_dir>
	cd <that_dir>
	cat > user.rc <<EOF
	export KNOX_TENANT_NAME=vanilla
	export KNOX_USERNAME=fred
	export KNOX_PASSWORD=holala
	export EPOUTA_TENANT_NAME=
	export EPOUTA_USERNAME=frhaziza
	export EPOUTA_PASSWORD=<password>
	EOF
	# The openstack user 'fred' must maybe be an admin on the tenant 'mmosler1'
	#
	#...and cue music!
	./micromosler.sh init --net # You'll be prompted at the end for a reboot.
	                            # Rebooting will help the partition to correctly resize to the disk size
	./micromosler.sh sync       # Wait a bit, servers are probably not done rebooting
	./micromosler.sh provision 
	
	# Later
	./micromosler.sh provision # to just re-configure µ-mosler. The task is idempotent.
	./micromosler.sh clean     # to destroy the VMs
	./micromosler.sh init      # to re-create them, but not the networks, routers, etc...
	./micromosler.sh sync      # Wait again a bit, still probably rebooting
	./micromosler.sh reset     # Cleanup inside the VMs
	./micromosler.sh provision # Shoot again...


# Go into the Virtual router

The virtual router is running as a network namespace on Knox.
The namespace name is a the form qrouter-<router_id>. We fetch the router id as follows.

	source [KE_FOLDER]/settings/common.sh
	MGMT_ROUTER_ID=$(neutron router-list | awk "/${OS_TENANT_NAME}-mgmt-router/ { print \$2 }")

In order to _go into the namespace_, we issue the following command. Note that the `-E` allows the environment variables to follow with us, in particular the SSH_AUTH_SOCK one, so that we can still use the ssh keys that were preloaded in the ssh agent.

	sudo -E ip netns exec qrouter-$MGMT_ROUTER_ID bash

