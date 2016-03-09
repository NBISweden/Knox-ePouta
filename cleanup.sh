#!/bin/sh


proj="$OS_TENANT_NAME"

nova  list  --fields id  | while read a machine c; do
  nova delete "$machine"
done

neutron router-list  -c id  -f value | while read router; do
  neutron router-delete "$router"
done

neutron subnet-list -c id -f value  | while read subnet; do
 neutron subnet-delete "$subnet"
done

neutron port-list -c id -f value | while read port; do
  neutron port-delete "$port"
done

neutron net-list  -c id  -f value | while read net; do
  neutron net-delete "$net"
done



neutron router-interface-delete  "$proj"-router "$proj"-subnet

neutron router-delete "$proj"-router
neutron subnet-delete "$proj"-subnet

neutron security-group-list -c id -f value | while read secgroup; do
  neutron security-group-delete "$secgroup"
done


nova keypair-list | while read a b c; do
  nova keypair-delete "$b"
done
