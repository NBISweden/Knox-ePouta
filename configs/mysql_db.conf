DELETE FROM mysql.user WHERE User='';
#DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;

# DROP DATABASE IF EXISTS nova;
# DROP DATABASE IF EXISTS neutron;
# DROP DATABASE IF EXISTS keystone;
# DROP DATABASE IF EXISTS glance;
# DROP DATABASE IF EXISTS heat;

CREATE DATABASE nova;
CREATE DATABASE keystone;
CREATE DATABASE glance;
CREATE DATABASE neutron;
CREATE DATABASE heat;

GRANT ALL PRIVILEGES ON nova.* to nova@localhost identified by 'nova';
GRANT ALL PRIVILEGES ON nova.* to nova@'%' identified by 'nova';

GRANT ALL PRIVILEGES ON neutron.* to neutron@localhost  identified by 'neutron';
GRANT ALL PRIVILEGES ON neutron.* to neutron@'%' identified by 'neutron';

GRANT ALL PRIVILEGES ON keystone.* to keystone@localhost identified by 'keystone';
GRANT ALL PRIVILEGES ON keystone.* to keystone@'%' identified by 'keystone';

GRANT ALL PRIVILEGES ON glance.* to glance@localhost identified by 'glance';
GRANT ALL PRIVILEGES ON glance.* to glance@'%' identified by 'glance';
      
GRANT ALL PRIVILEGES ON heat.* to heat@localhost identified by 'heat';
GRANT ALL PRIVILEGES ON heat.* to heat@'%' identified by 'heat';

