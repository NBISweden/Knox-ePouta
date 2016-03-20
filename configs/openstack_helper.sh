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
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

/usr/bin/mysqladmin -u root password mysql || true
/usr/bin/mysqladmin -u root -h openstack-controller password mysql || true

/usr/bin/mysql -u root -pmysql -e "create database nova  DEFAULT CHARACTER SET = 'utf8' DEFAULT COLLATE 'utf8_general_ci';"
/usr/bin/mysql -u root -pmysql -e "create database keystone  DEFAULT CHARACTER SET = 'utf8' DEFAULT COLLATE 'utf8_general_ci';"
/usr/bin/mysql -u root -pmysql -e "create database glance  DEFAULT CHARACTER SET = 'utf8' DEFAULT COLLATE 'utf8_general_ci';"
/usr/bin/mysql -u root -pmysql -e "create database heat  DEFAULT CHARACTER SET = 'utf8' DEFAULT COLLATE 'utf8_general_ci';"
/usr/bin/mysql -u root -pmysql -e "create database neutron;"

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
su -s /bin/sh -c "nova-manage db sync" nova

su -s /bin/sh -c "heat-manage db_sync" heat

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf  --config-file /etc/neutron/plugin.ini upgrade 5ac1c354a051" neutron

chkconfig memcached on  || true
/sbin/service memcached restart || true

chkconfig openstack-keystone on || true
/sbin/service openstack-keystone restart || true

keystone role-create --name=admin
keystone role-create --name=service
keystone role-create --name=_member_

keystone tenant-create --name=admin --description="Admin Tenant"
keystone user-role-add --user=admin --tenant=admin --role=admin
keystone user-role-add --user=admin --role=_member_ --tenant=admin

keystone tenant-create --name=services --description="Service Tenant"

keystone user-role-add --user=glance --role=admin --tenant=services
keystone user-role-add --user=nova --role=admin --tenant=services
keystone user-role-add --user=heat --role=admin --tenant=services
keystone user-role-add --user=neutron --role=admin --tenant=services
keystone user-role-add --user=keystone --role=admin --tenant=services




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
  --publicurl=http://openstack-controller:9292 \
  --internalurl=http://openstack-controller:9292 \
  --adminurl=http://openstack-controller:9292


keystone service-create --name=nova --type=compute \
  --description="OpenStack Compute" 

keystone endpoint-create \
  --service-id=$(keystone service-list | awk '/ compute / {print $2}') \
  --publicurl=http://openstack-controller:8774/v2/%\(tenant_id\)s \
  --internalurl=http://openstack-controller:8774/v2/%\(tenant_id\)s \
  --adminurl=http://openstack-controller:8774/v2/%\(tenant_id\)s

keystone service-create --name neutron --type network --description "OpenStack Networking"

keystone endpoint-create \
  --service-id $(keystone service-list | awk '/ network / {print $2}') \
  --publicurl http://openstack-controller:9696 \
  --adminurl http://openstack-controller:9696 \
  --internalurl http://openstack-controller:9696

keystone service-create --name=heat --type=orchestration \
  --description="Orchestration"

keystone endpoint-create \
  --service-id=$(keystone service-list | awk '/ orchestration / {print $2}') \
  --publicurl=http://openstack-controller:8004/v1/%\(tenant_id\)s \
  --internalurl=http://openstack-controller:8004/v1/%\(tenant_id\)s \
  --adminurl=http://openstack-controller:8004/v1/%\(tenant_id\)s

keystone service-create --name=heat-cfn --type=cloudformation \
  --description="Orchestration CloudFormation"

keystone endpoint-create \
  --service-id=$(keystone service-list | awk '/ cloudformation / {print $2}') \
  --publicurl=http://openstack-controller:8000/v1 \
  --internalurl=http://openstack-controller:8000/v1 \
  --adminurl=http://openstack-controller:8000/v1


# Start services and make sure they are enabled at reboots.
for p in heat-api heat-api-cfn heat-engine nova-api nova-scheduler nova-conductor glance-api glance-registry ; do
    chkconfig openstack-$p on 
    /sbin/service openstack-$p restart
done

chkconfig neutron-server on
/sbin/service neutron-server restart


chkconfig httpd on
/sbin/service httpd restart


. /root/.keystonerc
#
neutron net-create public-net --shared --router:external=True

neutron subnet-create public-net --name public-subnet   --allocation-pool start=172.18.0.30,end=172.18.0.200  --disable-dhcp --gateway 172.18.0.1  172.18.0.0/24

exit 0
