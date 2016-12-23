# Create a veth pair for external access to the virtual router
$ ip link add gw type veth peer name mm

# Add the gw interface to the virtual router
$ ip link set gw netns qrouter-@uuid

# Give an ip to `mm`
$ ip addr add 10.5.0.1/24 dev mm
