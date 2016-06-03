# -*-sh-*-

# This script installs mysql and configures it for openstack

- name: Install Mysql package
  yum: name={{ item }} state=installed
  with_items:
   - mysql-server
   - MySQL-python

# - name: Start Mysql Service
#   service: name=mysqld state=started enabled=yes

# - name: Create Application Database
#   mysql_db: name={{ dbname }} state=present

# - name: Create Application DB User
#   mysql_user: name={{ dbuser }} password={{ upassword }} priv=*.*:ALL host='%' state=present

# - name: Stopping Openstack Services
#   service: name={{ item }} state=stopped
#   with_items:
#     - openstack-keystone
#     - openstack-heat-api
#     - openstack-heat-api-cfn
#     - openstack-heat-engine
#     - openstack-nova-api
#     - openstack-nova-scheduler
#     - openstack-nova-conductor
#     - openstack-glance-api
#     - neutron-server
#     - openstack-glance-registry
#     - mysqld
    
- service: name=mysqld state=stopped

- name: Create MySQL configuration file
  template: src={{ mm_home }}/configs/my.cnf.j2 dest=/etc/my.cnf

- name: Removing databases by hand
  # Or check that: http://hakunin.com/six-ansible-practices#path-to-success-3
  shell: rm -rf /var/lib/mysql; mkdir --mode=0755 /var/lib/mysql; chown mysql:mysql /var/lib/mysql

- service: name=mysqld state=restarted

- name: MySQL root password
  shell: /usr/bin/mysqladmin -u root -h {{ item }} password 'mysql'
  with_items:
    - localhost
    - openstack-controller
  # ignore_errors: true

# Not dropping the .my.cnf file in /root

- name: Copying MySQL database setup file
  copy: src={{ mm_home }}/configs/mysql_db.conf dest=/tmp/openstack-db.sql

- name: MySQL Databases setup
  shell: mysql -u root -pmysql < /tmp/openstack-db.sql
  register: db_ready

