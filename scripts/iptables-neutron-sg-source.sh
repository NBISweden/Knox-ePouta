[compute-node]$ iptables -S neutron-linuxbri-s@uuid
-N neutron-linuxbri-s@uuid
# Allow traffic from defined IP/MAC pairs.
-A neutron-linuxbri-s@uuid @highlight{-s 10.101.128.100/32} \
                           @highlight{-m mac --mac-source FA:16:3E:8B:C4:6A} \
			   -j RETURN
# Drop traffic without an IP/MAC allow rule
-A neutron-linuxbri-s@uuid -j DROP
