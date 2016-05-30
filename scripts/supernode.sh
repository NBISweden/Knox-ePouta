# - name: Copying mosler config files
#   copy: src={{ mosler_home }}/supernode/{{ item }} dest=/usr/local/bin/
#   with_items:
#     - fix_proj.sh
#     - import_user
#     - passwd_line
#     - queue_responder
#     - remove_stack.sh
#     - sync_exporters
#     - sync_grantfile
#     - tenant-valid
#     - uppmax-links.sh
#     - uppmax-sync.sh

# - copy: src={{ mosler_home }}/supernode/{{ item }} dest=/usr/local/sbin/ mode=0755
#   with_items:
#     - project_gid
#     - project_ips
#     - project_members
#     - refreshimage
#     - setup_homedir.sh
#     - thinlinc_proj_setup

# - copy: src={{ mosler_home }}/supernode/{{ item }} dest=/usr/local/bin/ mode=0755
#   with_items:
#     - create_project.sh
#     - create_heat_template.sh
#     - create_omd_config.sh
#     - get_vlan.sh
#     - heat_add_compute.sh

# - file: path=/usr/local/heat state=directory
# - copy: src={{ mm_home }}/configs/{{ item }} dest=/usr/local/heat/ mode=0755
#   with_items:
#     - mosler-template-resources-private_net-only
#     - mosler-template-resources-network
#     - mosler-template-resources-secgroups
#     - mosler-template-resources-loginnode
#     - mosler-template-resources-servicenode
#     - mosler-template-parameters

# - name: Removing any 'public-net'
#   shell: . /root/.keystonerc && neutron net-list -F id -F name | awk '/ public-net / {print $2}' | while read netid; do neutron net-delete ${netid}; done
#   when: neutron_started
# - name: Creating public network in neutron & updating the mosler-heat parameters
#   shell: . /root/.keystonerc && extnet=$(neutron net-create public-net --router:external True | awk '/ id / {print $4}') && sed -i -e "s/__EXT_NET__/$extnet/"  /usr/local/heat/mosler-template-parameters
# - name: Creating public subnet network in neutron
#   shell: . /root/.keystonerc && neutron subnet-create public-net --name public-subnet --allocation-pool start=172.18.0.30,end=172.18.0.200 --disable-dhcp --gateway 172.18.0.1  172.18.0.0/24
