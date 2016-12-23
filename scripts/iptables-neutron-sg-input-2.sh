[compute-node]$ iptables -S neutron-linuxbri-ib83935a5-3
-N neutron-linuxbri-i@uuid
# Direct packets associated with a known session to the RETURN chain.
-A neutron-linuxbri-i@uuid -m state \
                           --state RELATED,ESTABLISHED \
			   -j RETURN
-A neutron-linuxbri-i@uuid -s 10.101.128.0/32 \
                           -p udp \
			   -m udp --sport 67 \
			   -m udp --dport 68 \
			   -j RETURN
-A neutron-linuxbri-i@uuid -s 10.101.0.0/16 \
                           -p icmp \
			   -j RETURN
-A neutron-linuxbri-i@uuid -s 10.101.0.0/16 \
                           -p tcp -m tcp \
			   -m multiport --dports 1:65535 \
			   -j RETURN
-A neutron-linuxbri-i@uuid -m set --match-set NIP@uuid src \
                           -j RETURN
# Drop packets that appear related to an existing connection 
# (e.g. TCP ACK/FIN) but do not have an entry in conntrack.
-A neutron-linuxbri-i@uuid -m state --state INVALID -j DROP
# Send unmatched traffic to the fallback chain.
-A neutron-linuxbri-i@uuid -j neutron-linuxbri-sg-fallback
