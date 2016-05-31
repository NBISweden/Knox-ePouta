# -*-sh-*-
---
# This playbook will install mysql and create db user and give permissions.

- name: Openstack utils and more
  yum: pkg=rabbitmq-server state=present

- name: Starting the Message Broker
  service: name=rabbitmq-server state=started

- name: Preparing the RabbitMQ user
  rabbitmq_user: state=present force=yes user=openstack password=rabbit configure_priv='.*' read_priv='.*' write_priv='.*'

