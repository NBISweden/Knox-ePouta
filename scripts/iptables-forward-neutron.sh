[compute-node] # iptables -S neutron-linuxbri-FORWARD
...
# Direct traffic from the VM interface to the security group chain.
-A neutron-linuxbri-FORWARD -m physdev --physdev-out tap<...> --physdev-is-bridged \
                            -j neutron-linuxbri-sg-chain
-A neutron-linuxbri-FORWARD -m physdev --physdev-in  tap<...> --physdev-is-bridged \
                            -j neutron-linuxbri-sg-chain
...
