#!/usr/bin/env bash

# Cleaning the listings
for machine in ${MACHINES[@]}; do : > ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]}; done

function copy {
    local machine=${FLOATING_IPs[$1]}
    local src=$2
    local dst=$3
    local mode=${4-''}

    # Exit if no parameter
    if [ -z "$src" ] || [ -z "$machine" ]; then return; fi

    if [ -e $src ]; then
	echo -n "$src" >> ${PROVISION_TMP}/copy.$1.$machine
	if [ -n "$dst" ]; then
	    echo -n ",$dst" >> ${PROVISION_TMP}/copy.$1.$machine
	    [ -n "$mode" ] && echo -n ",$mode" >> ${PROVISION_TMP}/copy.$1.$machine
	fi
	echo '' >> ${PROVISION_TMP}/copy.$1.$machine # new line
    else
	echo "ERROR: $src not found [$1 - $machine]"
    fi
}

#########################################################################
CONFIGS=${MM_HOME}/configs
[ "$VERBOSE" = "yes" ] && echo -e "\tPreparing lists"

# LDAP files
copy ldap ${CONFIGS}/ldap_conf

# DB files
copy openstack-controller ${CONFIGS}/openstack_db.sql

# Thinlinc
copy thinlinc-master ${TL_HOME%%/}/ # Make sure there is a / at the end
copy thinlinc-master ${CONFIGS}/tl_answers

# Openstack common files
for m in {openstack-controller,networking-node,compute1,compute2,compute3,supernode}; do
    copy $m ${CONFIGS}/rdo-release.repo /etc/yum.repos.d/rdo-release.repo
    copy $m ${CONFIGS}/RPM-GPG-KEY-Icehouse-SIG /etc/pki/rpm-gpg/RPM-GPG-KEY-Icehouse-SIG
    copy $m ${CONFIGS}/keystonerc /root/.keystonerc
done

# Openstack controller
copy openstack-controller ${MOSLER_MISC%%/}/ # Make sure there is a / at the end

copy openstack-controller ${CONFIGS}/neutron.conf           /etc/neutron/neutron.conf
copy openstack-controller ${CONFIGS}/keystone.conf          /etc/keystone/keystone.conf
copy openstack-controller ${CONFIGS}/plugin.ini             /etc/neutron/plugin.ini
copy openstack-controller ${CONFIGS}/ml2.ini                /etc/neutron/plugins/ml2/ml2.ini
copy openstack-controller ${CONFIGS}/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
copy openstack-controller ${CONFIGS}/nova.conf              /etc/nova/nova.conf
copy openstack-controller ${CONFIGS}/glance-api.conf        /etc/glance/glance-api.conf
copy openstack-controller ${CONFIGS}/glance-registry.conf   /etc/glance/glance-registry.conf
copy openstack-controller ${CONFIGS}/heat.conf              /etc/heat/heat.conf
copy openstack-controller ${CONFIGS}/local_settings         /etc/openstack-dashboard/local_settings

# Openstack neutron
copy networking-node ${CONFIGS}/neutron.conf /etc/neutron/neutron.conf
copy networking-node ${CONFIGS}/plugin.ini /etc/neutron/plugin.ini
copy networking-node ${CONFIGS}/ml2.ini /etc/neutron/plugins/ml2/ml2.ini
copy networking-node ${CONFIGS}/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini

# Openstack Copmute nodes
for c in compute{1..3}; do
    copy $c ${CONFIGS}/neutron.conf           /etc/neutron/neutron.conf
    copy $c ${CONFIGS}/plugin.ini             /etc/neutron/plugin.ini
    copy $c ${CONFIGS}/ml2.ini                /etc/neutron/plugins/ml2/ml2.ini
    copy $c ${CONFIGS}/ovs_neutron_plugin.ini /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini
    copy $c ${CONFIGS}/nova.conf              /etc/nova/nova.conf
done

# Supernode
FILES=
for f in {fix_proj.sh,import_user,passwd_line,queue_responder,remove_stack.sh,sync_exporters,sync_grantfile,tenant-valid,uppmax-links.sh,uppmax-sync.sh}; do
    copy supernode ${MOSLER_HOME}/supernode/$f /usr/local/bin/$f
done

for f in {project_gid,project_ips,project_members,refreshimage,setup_homedir.sh,thinlinc_proj_setup}; do
    copy supernode ${MOSLER_HOME}/supernode/$f /usr/local/sbin/$f 0755
done

for f in {create_project.sh,create_heat_template.sh,create_omd_config.sh,get_vlan.sh,heat_add_compute.sh}; do
    copy supernode ${MOSLER_HOME}/supernode/$f /usr/local/bin/$f 0755
done

# Make sure /usr/local/heat exists on supernode
for f in {mosler-template-resources-private_net-only,mosler-template-resources-network,mosler-template-resources-secgroups,mosler-template-resources-loginnode,mosler-template-resources-servicenode,mosler-template-parameters}; do
    copy supernode ${CONFIGS}/$f /usr/local/heat/$f 0755
done

#########################################################################

# Preparing the drop folder
for machine in ${MACHINES[@]}; do ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} mkdir -p ${VAULT}; done

declare -A RSYNC_PIDS
for machine in ${MACHINES[@]}
do
    if [ -f ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]} ]; then
	for line in $(cat ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]})
	do
	    #IFS=',' read -ra LINE <<< "$line"
	    LINE=(${line//,/ }) # replace , with space and make it an array
	    src=${LINE[0]}
	    set -x -e # Print commands && exit if errors
	    rsync -av -e "ssh -F ${SSH_CONFIG}" $src ${FLOATING_IPs[$machine]}:${VAULT}/.
	    dst=${LINE[1]}
	    mode=${LINE[2]}
	    if [ -n "$dst" ]; then 
		if [ -n "$mode" ]; then
		    ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} "sudo rsync ${VAULT}/${src##*/} $dst && sudo chmod $mode $dst"
		else
		    ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} "sudo rsync ${VAULT}/${src##*/} $dst"
		fi
	    fi
	done > ${PROVISION_TMP}/rsync.$machine.${FLOATING_IPs[$machine]} 2>&1 &
	RSYNC_PIDS[$machine]=$!
    fi
done

# Wait for all the copying to finish
[ "$VERBOSE" = "yes" ] && echo -e "\tWaiting for the files to be copied (${#RSYNC_PIDS[@]} background jobs)"
for job in ${!RSYNC_PIDS[@]}; do echo -e "\t\t* on $job [PID: ${RSYNC_PIDS[$job]}]"; done
FAIL=""
for job in ${!RSYNC_PIDS[@]}
do
    wait ${RSYNC_PIDS[$job]} || FAIL+=" $job (${RSYNC_PIDS[$job]}),"
    echo -n "."
done
[ "$VERBOSE" = "yes" ] && echo " Files copied"
[ -n "$FAIL" ] && echo "Failed copying:$FAIL"
