#!/bin/bash

. /root/.keystonerc

neutron net-list | grep -i public-net || neutron net-create public-net --router:external True 
extnet=`neutron net-show "public-net" | sed -ne '/\sid\s/ s/.*\s\([-0-9a-f][-0-9a-f]*\)\s.*/\1/ p'`

sed -i -e "s/d97c3bd7-d5ff-495d-80c8-2e62685b2552/$extnet/"  /usr/local/heat/mosler-template-parameters

exit 0

