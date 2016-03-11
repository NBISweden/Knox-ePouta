#!/bin/sh

if [  -f /root/openstack_setup ]; then
  exit 0
fi

OS_SERVICE_TOKEN=0123456789abcdef0123456789abcdef
OS_SERVICE_ENDPOINT=http://openstack-controller:35357/v2.0

export OS_SERVICE_TOKEN
export OS_SERVICE_ENDPOINT

cat - > /root/.keystonerc <<EOF
export OS_USERNAME=admin 
export OS_TENANT_NAME=admin
export OS_PASSWORD=admin
export OS_AUTH_URL=http://openstack-controller:35357/v2.0/
EOF

/sbin/service mysqld start
/sbin/service rabbitmq-server start
rabbitmqctl add_user openstack rabbit || true

/usr/bin/mysqladmin -u root password mysql || true
/usr/bin/mysqladmin -u root -h openstack-controller password mysql || true
/usr/bin/mysqladmin -u root -pmysql create nova || true
/usr/bin/mysqladmin -u root -pmysql create keystone || true
/usr/bin/mysqladmin -u root -pmysql create glance  || true
/usr/bin/mysqladmin -u root -pmysql create neutron || true
/usr/bin/mysqladmin -u root -pmysql create heat || true
/usr/bin/mysql -u root -pmysql -e "grant all privileges on nova.* to nova@localhost identified by 'nova';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on neutron.* to neutron@localhost  identified by 'neutron';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on keystone.* to keystone@localhost identified by 'keystone';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on glance.* to glance@localhost identified by 'glance';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on heat.* to heat@localhost identified by 'heat';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on nova.* to nova@'%' identified by 'nova';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on neutron.* to neutron@'%' identified by 'neutron';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on keystone.* to keystone@'%' identified by 'keystone';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on glance.* to glance@'%' identified by 'glance';"
/usr/bin/mysql -u root -pmysql -e "grant all privileges on heat.* to heat@'%' identified by 'heat';"
/usr/bin/mysql -u root -pmysql mysql -e "delete from user where user='';"

sleep 3

/sbin/service mysqld restart

su -s /bin/sh -c "keystone-manage db_sync" keystone
su -s /bin/sh -c "glance-manage db_sync" glance
#su -s /bin/sh -c "nova-manage db sync" nova

su -s /bin/sh -c "heat-manage db_sync" heat

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf  --config-file /etc/neutron/plugin.ini upgrade head" neutron

chkconfig openstack-keystone on || true

/sbin/service openstack-keystone restart || true

keystone role-create --name=admin
keystone role-create --name=_member_

keystone tenant-create --name=admin --description="Admin Tenant"
keystone user-role-add --user=admin --tenant=admin --role=admin
keystone user-role-add --user=admin --role=_member_ --tenant=admin

keystone tenant-create --name=service --description="Service Tenant"

keystone service-create --name=keystone --type=identity \
  --description="OpenStack Identity"

keystone endpoint-create \
  --service-id=$(keystone service-list | awk '/ identity / {print $2}') \
  --publicurl=http://oepnstack-controller:5000/v2.0 \
  --internalurl=http://openstack-controller:5000/v2.0 \
  --adminurl=http://openstack-controller:35357/v2.0


keystone service-create --name=glance --type=image \
  --description="OpenStack Image Service"

keystone endpoint-create \
  --service-id=$(keystone service-list | awk '/ image / {print $2}') \
  --publicurl=http:/openstack-controller:9292 \
  --internalurl=http:/openstack-controller:9292 \
  --adminurl=http:/openstack-controller:9292


keystone service-create --name=nova --type=compute \
  --description="OpenStack Compute" keystone endpoint-create \
  --service-id=$(keystone service-list | awk '/ compute / {print $2}') \
  --publicurl=http:/openstack-controller:8774/v2/%\(tenant_id\)s \
  --internalurl=http:/openstack-controller:8774/v2/%\(tenant_id\)s \
  --adminurl=http:/openstack-controller:8774/v2/%\(tenant_id\)s

keystone endpoint-create \
  --service-id $(keystone service-list | awk '/ network / {print $2}') \
  --publicurl http:/openstack-controller:9696 \
  --adminurl http:/openstack-controller:9696 \
  --internalurl http:/openstack-controller:9696


# Start services and make sure they are enabled at reboots.
for p in heat-api heat-engine nova-api nova-scheduler nova-conductor glance-api glance-registry ; do
    chkconfig openstack-$p on 
    /sbin/service openstack-$p start
done

for p in server openvswitch-agent dhcp-agent l3-agent ovs-cleanup metadata-agent; do
    chkconfig neutron-$p on 
    /sbin/service neutron-$p start
done

chkconfig httpd on
/sbin/service httpd start
