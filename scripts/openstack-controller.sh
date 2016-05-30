# -*-sh-*-

set +v
source ${SCRIPT_FOLDER:-.}/common.sh
set +v
source ${SCRIPT_FOLDER:-.}/openstack-common.sh
#set -v

{ echo "Openstack utils and more"
  PACKAGES=\
openstack-dashboard openstack-keystone openstack-heat-engine openstack-heat-api openstack-heat-api-cfn openstack-glance \
memcached
#     # - openstack-nova
#     # - openstack-neutron
#     # - openstack-neutron-ml2
#     # - openstack-neutron-openvswitch
  yum -y install $PACKAGES
}


{ echo "Openstack Mosler dashboard"
PACKAGES=\
/tmp/misc/Django14-1.4.21-1.el6.noarch.rpm \
/tmp/misc/mosler-dashboard-2-5.i386.rpm \
/tmp/misc/nginx-1.8.1-1.el6.ngx.x86_64.rpm
  yum -y install $PACKAGES
}

echo "Copying config files"
rsync rsync/neutron.conf           /etc/neutron/neutron.conf
rsync rsync/keystone.conf          /etc/keystone/keystone.conf
rsync rsync/plugin.ini             /etc/neutron/plugin.ini
rsync rsync/ml2.ini                /etc/neutron/plugins/ml2/ml2.ini
rsync rsync/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
rsync rsync/nova.conf              /etc/nova/nova.conf
rsync rsync/glance-api.conf        /etc/glance/glance-api.conf
rsync rsync/glance-registry.conf   /etc/glance/glance-registry.conf
rsync rsync/heat.conf              /etc/heat/heat.conf
rsync rsync/local_settings         /etc/openstack-dashboard/local_settings

echo "Memcached service"
service memcached restart
chkconfig memcached on

echo "Preparing the databases"
su -s /bin/sh -c 'keystone-manage db_sync' keystone
su -s /bin/sh -c 'glance-manage db_sync' glance
su -s /bin/sh -c 'nova-manage db sync' nova
su -s /bin/sh -c 'heat-manage db_sync' heat
su -s /bin/sh -c 'neutron-db-manage --config-file /etc/neutron/neutron.conf  --config-file /etc/neutron/plugin.ini upgrade 5ac1c354a051' neutron

echo "Keystone service"
service openstack-keystone restart
chkconfig openstack-keystone on

OS_SERVICE_TOKEN=0123456789abcdef0123456789abcdef
OS_SERVICE_ENDPOINT=http://openstack-controller:35357/v2.0

echo "Keystone roles"
for role in admin service # - _member_ # already created by 'keystone-manage db_sync'
do
    keystone role-create --name=$role
done

echo "Keystone tenants"
keystone tenant-create --name=admin --description='Admin Tenant'
keystone tenant-create --name=services --description='Service Tenant'

echo "Keystone roles attribution"
keystone user-role-add --user=admin    --tenant=admin    --role=admin
keystone user-role-add --user=admin    --tenant=admin    --role=_member_
keystone user-role-add --user=keystone --tenant=services --role=admin
keystone user-role-add --user=nova     --tenant=services --role=admin
keystone user-role-add --user=neutron  --tenant=services --role=admin
keystone user-role-add --user=glance   --tenant=services --role=admin
keystone user-role-add --user=heat     --tenant=services --role=admin
        
echo "Keystone service creation"
keystone service-create --name=keystone --type=identity       --description='OpenStack Identity'
keystone service-create --name=glance   --type=image          --description='OpenStack Image Service'
keystone service-create --name=nova     --type=compute        --description='OpenStack Compute'
keystone service-create --name=neutron  --type=network        --description='OpenStack Networking'
keystone service-create --name=heat     --type=orchestration  --description='Orchestration'
keystone service-create --name=heat-cfn --type=cloudformation --description='Orchestration CloudFormation'


echo "Keystone endpoints creation"
for line in { identity::5000/v2.0,
	      image::9292
	      compute::'8774/v2/%\(tenant_id\)s'
	      network::9696
	      orchestration::'8004/v1/%\(tenant_id\)s'
	      cloudformation::8000/v1}
do
    _service=${line%::*}
    _addr=http://openstack-controller:${line#*::}
    keystone endpoint-create --service-id=$(keystone service-list | awk "/ ${_service} / {print $2}") --publicurl=${_addr} --internalurl=${_addr} --adminurl=${_addr}
done

unset OS_SERVICE_TOKEN
unset OS_SERVICE_ENDPOINT

echo "Starting Openstack Services"
for s in {openstack-heat-api,openstack-heat-api-cfn,openstack-heat-engine,openstack-nova-api,openstack-nova-scheduler,openstack-nova-conductor,openstack-glance-api,neutron-server,openstack-glance-registry,httpd}
do
    service $s restart 
    chkconfid $s on
done

echo "Removing any old image from Glance"
rm -rf /var/lib/glance/images/*

echo "Adding the images to Glance"
for i in {project-computenode-stable,project-loginnode-stable,topolino-q-stable}
do
    . /root/.keystonerc && glance image-create --file rsync/$i --disk-format qcow2 --container-format bare  --name "$i" --is-public True
done

echo "Removing existing Mosler flavors"
. /root/.keystonerc && { nova flavor-list | awk '/ mosler\./ {print $2}' | while read flavor; do nova flavor-delete $flavor; done }

echo "Adding Mosler flavors"
. /root/.keystonerc && \
    {
	nova flavor-create mosler.1core   auto 500 10 1
	nova flavor-create mosler.2cores  auto 500 10 1
	nova flavor-create mosler.4cores  auto 500 10 1
	nova flavor-create mosler.8cores  auto 500 10 1
	nova flavor-create mosler.16cores auto 500 10 1
    }

. /root/.keystonerc && nova aggregate-create service-and-login serv-login
. /root/.keystonerc && nova aggregate-add-host service-and-login compute1.novalocal
