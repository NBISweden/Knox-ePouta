$ source <ePouta.credentials>

$ neutron subnet-show epouta-subnet
+-------------------+--------------------------------------------------+
| Field             | Value                                            |
+-------------------+--------------------------------------------------+
| allocation_pools  | {"start": "10.101.0.2", "end": "10.101.127.255"} |
| cidr              | 10.101.0.0/16                                    |
| dns_nameservers   | 10.101.128.0                                     |
| enable_dhcp       | True                                             |
| gateway_ip        | 10.101.0.1                                       |
| host_routes       |                                                  |
| id                | <...>                                            |
| ip_version        | 4                                                |
| name              | <epouta-subnet>                                  |
| network_id        | <...>                                            |
| subnetpool_id     |                                                  |
| tenant_id         | <...>                                            |
+-------------------+--------------------------------------------------+
