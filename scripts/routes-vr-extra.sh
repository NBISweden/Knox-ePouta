# In the virtual router
$ ip route add <Knox-openstack>/32   via 10.5.0.1 dev gw
$ ip route add <ePouta-openstack>/32 via 10.5.0.1 dev gw
$ ip route add <dns>/32              via 10.5.0.1 dev gw
$ ip route add <proxy>/32            via 10.5.0.1 dev gw
