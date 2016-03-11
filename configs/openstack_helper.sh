#!/bin/sh

if [  -f /root/openstack_setup ]; then
  exit 0
fi

OS_SERVICE_TOKEN=0123456789abcdef
OS_SERVICE_ENDPOINT=http://openstack-controller:35357/v2.0

export OS_SERVICE_TOKEN
export OS_SERVICE_ENDPOINT

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

su -s /bin/sh -c "keystone-manage db_sync" keystone
chkconfig openstack-keystone on || true
/sbin/service openstack-keystone start || true

keystone user-create --name=admin --pass=admin
keystone role-create --name=admin
keystone tenant-create --name=admin --description="Admin Tenant"
keystone user-role-add --user=admin --tenant=admin --role=admin
keystone user-role-add --user=admin --role=_member_ --tenant=admin



touch /root/openstack_setup
