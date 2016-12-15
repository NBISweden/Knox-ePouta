# In the virtual router namespace
# Give an ip to 'gw', and bring it up
# Note: it brings 'mm' up in the root namespace too
$ ip addr add 10.5.0.2/24 dev gw
$ ip link set dev gw up

