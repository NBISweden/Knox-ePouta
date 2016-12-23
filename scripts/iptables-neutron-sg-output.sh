[compute-node]$ iptables -S neutron-linuxbri-o@uuid
-N neutron-linuxbri-o@uuid
# Allow DHCP client traffic.
-A neutron-linuxbri-o@uuid -p udp \
                           -m udp --sport 68 \
			   -m udp --dport 67 \
			   -j RETURN
-A neutron-linuxbri-o@uuid -j neutron-linuxbri-s@uuid

# Prevent DHCP Spoofing by VM.
-A neutron-linuxbri-o@uuid -p udp \
                           -m udp --sport 67 \
			   -m udp --dport 68 \
			   -j DROP
# Direct packets associated with a known session to the RETURN chain.
-A neutron-linuxbri-o@uuid -m state \
                           --state RELATED,ESTABLISHED \
			   -j RETURN
-A neutron-linuxbri-o@uuid -j RETURN # <--- Eh?
# Drop packets that appear related to an existing connection
# (e.g. TCP ACK/FIN) but do not have an entry in conntrack.
-A neutron-linuxbri-o@uuid -m state --state INVALID -j DROP
# Send unmatched traffic to the fallback chain.
-A neutron-linuxbri-o@uuid -j neutron-linuxbri-sg-fallback

[compute-node]$ iptables -S neutron-linuxbri-sg-fallback
-N neutron-linuxbri-sg-fallback
# Default drop rule for unmatched traffic.
-A neutron-linuxbri-sg-fallback -j DROP
