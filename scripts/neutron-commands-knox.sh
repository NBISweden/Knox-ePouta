$ source <Knox.credentials>

# Create a router (Note its ID)
$ neutron router-create knox-router

# Create a network (on VLAN 1203)
$ neutron net-create --provider:network_type vlan \
                     --provider:physical_network vlan \
                     --provider:segmentation_id 1203 \
                     knox-net

# Specify the IP range
$ neutron subnet-create \
          --name knox-subnet \
          --allocation-pool start=10.101.128.0,end=10.101.255.254 \
          --gateway 10.101.0.1 \
          knox-net 10.101.0.0/16

# Add an interface in the router for that "101" network
$ neutron router-interface-add knox-router knox-subnet
