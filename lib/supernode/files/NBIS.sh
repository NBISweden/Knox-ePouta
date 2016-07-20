#!/bin/sh

source /root/.keystonerc
##############################################################
# Create project NBIS. Users come from ldap.
##############################################################

# Wait for the 3 glance images
function wait_for_images {
    local -i t=${1:-30} # default: 30 seconds, well...if you don't count the backoff...
    local -i backoff=1
    local -i stride=20
    while (( t > 0 )) ; do
	echo -e "Time left: $t"
	ans=$(glance image-list | awk '/ active /' | wc -l)
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

if ! keystone tenant-get NBIS; then
    /usr/local/bin/create_project.sh NBIS
fi

# add user to project, and fix the thinlinc account for it
export OS_TENANT_NAME=NBIS

ssh root@ldap ldapsearch -h ldap -b ou=Users,dc=mosler,dc=nbis,dc=se uid -x | grep ^uid: | while read a b; do
    case "$b" in
	admin|glance|glance|heat|keystone|neutron|nova) : ;;
	*)
	    echo "User: $b"
	    keystone user-role-add --tenant NBIS --role _member_ --user "$b"
	    ssh root@thinlinc-master /usr/local/sbin/establish_user "$b" < /dev/null ;;
    esac
done


keystone user-role-add --user=export1 --tenant=NBIS --role="exporter" >/dev/null
