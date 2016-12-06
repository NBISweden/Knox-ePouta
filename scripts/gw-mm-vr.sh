# Give an ip to `gw`, and bring it up
[virtual-router] # ip addr add 10.5.0.2/24 dev gw
                 # ip link set dev gw up

# Note: that'll bring `mm` up in the root namespace too
