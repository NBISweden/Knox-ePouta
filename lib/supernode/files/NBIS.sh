#!/bin/sh 

set -e -x
source /root/.keystonerc

##############################################################
# Create project NBIS. Users come from ldap.
##############################################################
# -w doesn't work on nc
function wait_port {
    local -i t=${3:-30} # default: 30 seconds, well...if you don't count the backoff...
    local -i backoff=1
    local -i stride=20
    while (( t > 0 )) ; do
	echo -e "Time left: $t"
	nc -4 -z -v $1 $2 && return 0
	(( t-=backoff ))
	sleep $backoff
        if (( (t % stride) == 0 )); then (( backoff*=2 )); fi
    done
    exit 1
}

# Wait for the 3 glance images
function wait_for_images {
    local -i t=${1:-30} # default: 30 seconds, well...if you don't count the backoff...
    local -i backoff=1
    local -i stride=20
    while (( t > 0 )) ; do
	echo -e "Time left: $t"
	ans=$(glance image-list | grep 00000000-0000-0000-0000 | awk '/ active /' | wc -l) # Quick fix with the grep
	[ "$ans" -eq 3 ] && return 0
	(( t-=backoff ))
	sleep $backoff
        if (( (t % stride) == 0 )); then (( backoff*=2 )); fi
    done
    exit 1
}
wait_for_images 300

function wait_for_flavors {
    local -i t=${1:-30} # default: 30 seconds, well...if you don't count the backoff...
    local -i backoff=1
    local -i stride=20
    while (( t > 0 )) ; do
	echo -e "Time left: $t"
	ans=$(nova flavor-list | awk '/ mosler\./' | wc -l)
	[ "$ans" -eq 5 ] && return 0
	(( t-=backoff ))
	sleep $backoff
        if (( (t % stride) == 0 )); then (( backoff*=2 )); fi
    done
    exit 1
}
wait_for_flavors 300

# Wait for heat
wait_port openstack-controller 8000 300

# If already exists
keystone tenant-get NBIS &>/dev/null && exit 1

# else
/usr/local/bin/create_project.sh NBIS

# add user to project, and fix the thinlinc account for it
export OS_TENANT_NAME=NBIS

ssh root@ldap ldapsearch -h ldap -b ou=Users,dc=mosler,dc=nbis,dc=se uid -x | grep ^uid: | while read a b; do
    case "$b" in
	admin|glance|heat|keystone|neutron|nova) : ;;
	*)
	    echo "User: $b"
	    keystone user-role-add --tenant NBIS --role _member_ --user "$b"
	    ssh root@thinlinc-master /usr/local/sbin/establish_user "$b" < /dev/null ;;
    esac
done

keystone user-role-add --tenant=NBIS --role=exporter --user=pi1
keystone user-role-add --tenant=NBIS --role=exporter --user=pi2
keystone user-role-add --tenant=NBIS --role=exporter --user=exporter1

VLAN=$(heat stack-show NBIS | awk '/private_seg_id/ {print $5}')
/usr/local/bin/create_nfs_share.sh NBIS $VLAN

# No need to call fix_userdata and fix_hostdata.
# They are called in some cron table.
