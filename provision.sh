#!/usr/bin/env bash

# Get credentials and machines settings
source ./settings.sh

DO_COPY=yes

function usage(){
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
SSH_KNOWN_HOSTS=${SCRIPT_FOLDER}/ssh_known_hosts.${OS_TENANT_NAME}

#############################################
## Calling ansible for the MicroMosler setup
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

# Adding the keys to the known_hosts file
true > ${SSH_KNOWN_HOSTS}
for name in ${MACHINES[@]}; do ssh-keyscan -4 ${FLOATING_IPs[$name]} >> ${SSH_KNOWN_HOSTS} 2>/dev/null; done
# Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.

########################################################################
# Aaaaannndddd....cue music!
########################################################################

if [ "$DO_COPY" = "yes" ]; then
    set -e # exit on errors
    [ "$VERBOSE" = "yes" ] && echo "Copying files"
    source ${SCRIPT_FOLDER}/copy.sh
fi

########################################################################

[ "$VERBOSE" = "yes" ] && echo "Configuring servers:"
declare -A PROVISION_PIDS
for machine in ${!PROVISION[@]}
do
    _SCRIPT=${SCRIPT_FOLDER}/${PROVISION[$machine]}.sh
    if [ -f ${_SCRIPT} ]; then
	_SCRIPT_DST=${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]}.sh
	[ "$VERBOSE" = "yes" ] && echo -e "\t* $machine"
	#(set -n -v; source ${_SCRIPT} 2>${_SCRIPT_DST})
	bash --norc -n -v ${_SCRIPT} 2>${_SCRIPT_DST}
	#{ source ${_SCRIPT}; set -n -v; } 2>&1 >${_SCRIPT_DST}
    else
	echo "Unknown script ${_SCRIPT}"
    fi
done

# set +n +v
# for machine in ldap
# do
#     if [ -f ${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]}.sh ]; then
# coproc $machine ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} "cat ${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]}.sh | base64 -d | sudo bash" > ${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]}.log 2>&1 &
# 	PROVISION_PIDS[$machine]=$!
#     fi
# done

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
