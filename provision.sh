#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings.sh

DO_COPY=yes

function usage {
    echo "Usage: $0 [--quiet|-q] [--no-copy|-n] -- ..."
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) VERBOSE=no;;
        --help|-h) usage; exit 0;;
        --no-copy|-n) DO_COPY=no;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done                                                                                              


# Note: Should exit the script if machines not yet available
# Should I test with an ssh connection (with timeout?)

mkdir -p ${PROVISION_TMP}
export SCRIPT_FOLDER=${MM_HOME}/scripts
export SSH_CONFIG=${PROVISION_TMP}/ssh_config.${OS_TENANT_NAME}
SSH_KNOWN_HOSTS=${PROVISION_TMP}/ssh_known_hosts.${OS_TENANT_NAME}

#############################################
## Calling the MicroMosler setup
#############################################

[ "$VERBOSE" = "yes" ] && echo -e "Creating the ssh config [in ${SSH_CONFIG}]"
cat > ${SSH_CONFIG} <<ENDSSHCFG
Host ${FLOATING_CIDR%0/24}*
	User centos
	ControlMaster auto
	ControlPersist 60s
	StrictHostKeyChecking no
	UserKnownHostsFile ${SSH_KNOWN_HOSTS}
	ForwardAgent yes
ENDSSHCFG

[ $VERBOSE = "yes" ] && echo -e "Adding the SSH keys to $SSH_KNOWN_HOSTS"
# if [ -f ${SSH_KNOWN_HOSTS} ]; then
#     # Cut the matching keys out
#     sed -n -i "/${FLOATING_CIDR%0/24}/d" ${SSH_KNOWN_HOSTS}
# else 
#     touch ${SSH_KNOWN_HOSTS}
# fi
:> ${SSH_KNOWN_HOSTS}
for name in ${MACHINES[@]}; do ssh-keyscan -4 ${FLOATING_IPs[$name]} >> ${SSH_KNOWN_HOSTS} 2>/dev/null; done
# Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.

########################################################################
# Aaaaannndddd....cue music!
########################################################################

export VAULT=vault

if [ "$DO_COPY" = "yes" ]; then

    [ "$VERBOSE" = "yes" ] && echo "Copying files"

    TL_HOME=${TL_HOME%%/}/
    MOSLER_MISC=${MOSLER_MISC%%/}/ # Make sure there is a / at the end
    export CONFIGS=${MM_HOME}/configs
    python -c 'import os;
import sys;
import jinja2;
sys.stdout.write(jinja2.Template(sys.stdin.read()).render(env=os.environ))' <files.jn2 >${PROVISION_TMP}/files

    # In order to avoid many concurrent ssh connections towards the same
    # server, we gather the file to copy and cluster them per server. 
    #
    # We will launch a new process, per machine, that copies the listed
    # files for that machine.
    
    # Cleaning the listings
    [ "$VERBOSE" = "yes" ] && echo "Preparing listings"
    for machine in ${MACHINES[@]}; do : > ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]}; done

    sed '/^$/d' ${PROVISION_TMP}/files | while IFS='' read -r line; do
	src=${line#*:}
	machine=${line%%:*}
	if [ -e $src ]; then
	    echo "$src" >> ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]}
	else
	    echo "\tIgnoring $src [for $machine]."
	fi
    done

    declare -A RSYNC_PIDS
    for machine in ${MACHINES[@]}
    do
	if [ -f ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]} ]; then
	    { # Scoping
		set -x -e # Print commands && exit if errors
		# Preparing the drop folder
		ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} mkdir -p ${VAULT}
		# Copying all files to the VAULT on that machine
		for f in $(cat ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]})
		do
		    rsync -av -e "ssh -F ${SSH_CONFIG}" $f ${FLOATING_IPs[$machine]}:${VAULT}/.
		done
	    } > ${PROVISION_TMP}/rsync.$machine.${FLOATING_IPs[$machine]} 2>&1 &
	    RSYNC_PIDS[$machine]=$!
	fi
    done

    # Wait for all the copying to finish
    [ "$VERBOSE" = "yes" ] && echo "Waiting for the files to be copied (${#RSYNC_PIDS[@]} background jobs)"
    for job in ${!RSYNC_PIDS[@]}; do echo -e "\t* on $job [PID: ${RSYNC_PIDS[$job]}]"; done
    FAIL=""
    for job in ${!RSYNC_PIDS[@]}
    do
	wait ${RSYNC_PIDS[$job]} || FAIL+=" $job (${RSYNC_PIDS[$job]}),"
	echo -n "."
    done
    [ "$VERBOSE" = "yes" ] && echo " Files copied"
    [ -n "$FAIL" ] && echo "Failed copying:$FAIL" && echo "Exiting..." && exit 1
fi

########################################################################

[ "$VERBOSE" = "yes" ] && echo "Configuring servers:"
declare -A PROVISION_PIDS
RENDER=${SCRIPT_FOLDER}/render.py
pushd ${SCRIPT_FOLDER}
for machine in ldap thinlinc storage opentack-controller #openstack-controller #${!PROVISION[@]}
do
     _SCRIPT=${PROVISION[$machine]}.jn2
    if [ -f ${_SCRIPT} ]; then
	# It will use the (exported) environment variables
	${RENDER} ${_SCRIPT} > ${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]}
	ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} 'sudo bash -e -x 2>&1' <${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]} 1>${PROVISION_TMP}/log.$machine.${FLOATING_IPs[$machine]} &
	#${_SCRIPT} | base64 -D > ${PROVISION_TMP}/log.$machine.${FLOATING_IPs[$machine]} 2>&1 &
	PROVISION_PIDS[$machine]=$!
    fi
done
popd

# Wait for all the copying to finish
[ "$VERBOSE" = "yes" ] && echo -e "\tWaiting for servers to be configured (${#PROVISION_PIDS[@]} background jobs)"
for job in ${!PROVISION_PIDS[@]}; do echo -e "\t\t* on $job [PID: ${PROVISION_PIDS[$job]}]"; done
FAIL=""
for job in ${!PROVISION_PIDS[@]}
do
    wait ${PROVISION_PIDS[$job]} || FAIL+=" $job (${PROVISION_PIDS[$job]}),"
    echo -n "."
done
[ "$VERBOSE" = "yes" ] && echo " Servers configured"
[ -n "$FAIL" ] && echo "Failed configuring:$FAIL"

