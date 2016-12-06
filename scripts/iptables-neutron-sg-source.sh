[compute-node] # iptables -S neutron-linuxbri-s<...>
-N neutron-linuxbri-s<...>
# Allow traffic from defined IP/MAC pairs.
-A neutron-linuxbri-s<...> -s 10.101.128.100/32 -m mac --mac-source FA:16:3E:8B:C4:6A -j RETURN
# Drop traffic without an IP/MAC allow rule
-A neutron-linuxbri-s<...> -j DROP
