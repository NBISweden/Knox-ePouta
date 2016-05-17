# µ-Mosler setup on Knox

This set of scripts allows you to (re)create the Mosler environment in an Openstack cluster.
This created set set of virtual machines is called µ-Mosler (*micro-mosler*). Our openstack cluster is called Knox.

## Requirements
You first need to create a file (named 'user.rc') in order to set up your openstack credentials. That file will contain 2 variables:

	OS_USERNAME=<username>
	OS_PASSWORD=<password>

The scripts define some variables (in `settings.sh`)
* `MM_HOME` (currently pointing to `$HOME/mosler-micro-mosler`)
* `TL_HOME` (currently pointing to `/home/jonas/thinlinc`)
* `MOSLER_HOME` (currently pointing to `/home/jonas/mosler-system-scripts`)
* `MOSLER_MISC` (currently pointing to `/home/jonas/misc`)
* `MOSLER_IMAGES` (currently pointing to `/home/jonas/mosler-images`)

The scripts assume that 
* A CentOS6 glance image is installed
* The [mosler-system-scripts](https://github.com/NBISweden/mosler-system-scripts) are available in `$MOSLER_HOME`
* The Thinlinc packages are available in `$TL_HOME`
* Some misc packages are available in `$MOSLER_MISC`
* And the mosler images are available in `$MOSLER_IMAGES`

## Execution
You can run `init.sh --all` in order to create the necessary routers,
networks and security groups, prior to creating the virtual machines.
It will start the VMs with proper IP information. In subsequent runs,
`init.sh` will only create the VMs.

Run the `provision.sh --with-packages` in order to set up the ansible
environment and play the playbooks. This script is divided in 2
phases: the first one installs the required packages, and the second
one configures the VMs. You can run without the --with-packages flag
in order to subsequently skip the package installation phase.

The `clean.sh` script can be run with the --all flag, to destroy
routers, networks, security groups and floating IPs.  Otherwise, it
only deletes the running VMs.

You can append the `-v` flag to get more verbose output.
