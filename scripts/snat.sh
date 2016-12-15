$ iptables -t nat -S # in the virtual router
[...]
-A POSTROUTING -o gw -j SNAT --to-source 10.5.0.2
[...]
