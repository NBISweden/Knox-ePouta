[controller]$ source <Knox.credentials>

# Create a router (Note its ID)
[controller]$ neutron router-create ${OS_TENANT_NAME}-mgmt-router
# This creates the above-mentioned qrouter-<...>

# Create a network (on VLAN 1203)
[controller]$ neutron net-create --provider:network_type vlan \
                                 --provider:physical_network vlan \
                                 --provider:segmentation_id 1203 \
                                 ${OS_TENANT_NAME}-mgmt-net

# Specify the IP range
[controller]$ neutron subnet-create --name ${OS_TENANT_NAME}-mgmt-subnet \
                      --allocation-pool start=10.101.128.1,end=10.101.255.254 \
                      --gateway 10.101.0.1 \
                      ${OS_TENANT_NAME}-mgmt-net 10.101.0.0/16

# Add an interface in the router for that 101 network
[controller]$ neutron router-interface-add ${OS_TENANT_NAME}-mgmt-router \
                                           ${OS_TENANT_NAME}-mgmt-subnet
                                           
# At this stage, the above-mentioned qdhcp-<...> is created.
