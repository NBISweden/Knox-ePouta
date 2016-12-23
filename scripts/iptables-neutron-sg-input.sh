[compute-node]$ iptables -S neutron-linuxbri-o@uuid
-N neutron-linuxbri-o@uuid
# Allow DHCP client traffic.
-A neutron-linuxbri-o@uuid -p udp \
                           -m udp --sport 68 \
			   -m udp --dport 67 \
			   -j RETURN
-A neutron-linuxbri-o@uuid -j neutron-linuxbri-s@uuid
