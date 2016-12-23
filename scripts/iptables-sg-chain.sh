[compute-node]$ iptables -S neutron-linuxbri-sg-chain
-N neutron-linuxbri-sg-chain
# Jump to the VM specific chain.
-A neutron-linuxbri-sg-chain -m physdev \
                             --physdev-out tap@uuid \
			     --physdev-is-bridged \
                             -j neutron-linuxbri-i@uuid
-A neutron-linuxbri-sg-chain -m physdev \
                             --physdev-in tap@uuid \
			     --physdev-is-bridged \
                             -j neutron-linuxbri-o@uuid
-A neutron-linuxbri-sg-chain -j ACCEPT
