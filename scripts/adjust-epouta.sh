[controller]$ source <ePouta.credentials>

[controller]$ neutron subnet-update UU-MOSLER-subnet \
                      --allocation-pools type=dict list=true
                      start=10.101.0.2,end=10.101.127.255 \
                      --dns-nameserver 10.101.128.0

[controller]$ neutron subnet-show UU-MOSLER-subnet
+-------------------+--------------------------------------------------+
| Field             | Value                                            |
+-------------------+--------------------------------------------------+
| allocation_pools  | {"start": "10.101.0.2", "end": "10.101.127.255"} |
| cidr              | 10.101.0.0/16                                    |
| dns_nameservers   | 10.101.128.0                                     |
| enable_dhcp       | True                                             |
| gateway_ip        | 10.101.0.1                                       |
| host_routes       |                                                  |
| id                | ffffffff-gggg-hhhh-iiii-jjjjjjjjjjjj             |
| ip_version        | 4                                                |
| name              | UU-MOSLER-subnet                                 |
| network_id        | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee             |
| subnetpool_id     |                                                  |
| tenant_id         | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa                 |
+-------------------+--------------------------------------------------+
