#!/usr/bin/env bash

# Get credentials and machines settings
HERE=$(dirname ${BASH_SOURCE[0]})
source $HERE/settings.sh

export TL_HOME MOSLER_HOME MOSLER_MISC MOSLER_IMAGES

export VAULT=vault
DO_COPY=yes

function usage {
    echo "Usage: $0 [options]"
    echo -e "\noptions are"
    echo -e "\t--vault <name>   \tName of the drop folder in the servers"
    echo -e "\t                 \tDefaults to '${VAULT}'"
    echo -e "\t--no-copy,-n     \tSkips the steps of syncing files to the servers"
    echo -e "\t--quiet,-q       \tRemoves the verbose output"
    echo -e "\t--help,-h        \tOutputs this message and exits"
    echo -e "\t-- ...           \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) VERBOSE=no;;
        --help|-h) usage; exit 0;;
        --no-copy|-n) DO_COPY=no;;
        --vault) VAULT=$2; shift;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done                                                                                              

mkdir -p ${PROVISION_TMP}

function say_ok {
    echo -e "[ \e[32m\xE2\x9C\x93\e[0m ]"
}
function say_fail {
    #echo -e " [ \e[31m\xE2\x98\xA0\e[0m ]"
    echo -e "[ \e[31m\xE2\x9C\x97\e[0m ]"
}
function thumb_up {
    [ -n "$1" ] && echo -n "$1 "
    echo -e "\xF0\x9F\x91\x8D"
}
function oups {
    [ -n "$1" ] && echo -n "$1 "
    echo -e "\e[31m\xF0\x9F\x9A\xAB\e[0m"
}

# Note: Should exit the script if machines not yet available
# Should I test with an ssh connection (with timeout?)
function check_connection {
    local ip=${FLOATING_IPs[$1]}
    local MAX=10
    local COUNTER=0

    if python -c "import socket;s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);s.settimeout(1.0); s.connect(('$ip', 22))" > /dev/null 2>&1 ; then
	say_ok
	exit 0
    else
	say_fail
	exit 1
    fi

    # trap "say_fail && exit 1" SIGINT
    # while : ; do
    # 	python -c "import socket;s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);s.settimeout(1.0); s.connect(('$ip', 22))" > /dev/null 2>&1 && say_ok && break
    # 	echo -n "."
    # 	#sleep 1 # socket.connect has already a timeout
    # 	(( COUNTER++ ))
    # 	(( $COUNTER > $MAX )) && say_fail && exit 1
    # done
    # exit 0
}
# Preparing the function. Not called yet.

[ "$VERBOSE" = "yes" ] && echo -e "Checking the connections:"
FAIL=""
for i in ${!MACHINES[@]}; do
    printf "\t* for %-23s" ${MACHINES[$i]}
    ( check_connection ${MACHINES[$i]} ) || { FAIL+=" ${MACHINES[$i]},"; unset MACHINES[$i]; }
done
if [ -n "$FAIL" ]; then
    oups "Filtering out:$FAIL"
else
    thumb_up "All connections are ready"
fi

#############################################
## SSH Configuration
#############################################
SSH_CONFIG=${PROVISION_TMP}/ssh_config.${OS_TENANT_NAME}
SSH_KNOWN_HOSTS=${PROVISION_TMP}/ssh_known_hosts.${OS_TENANT_NAME}

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

export CONFIGS=${MM_HOME}/configs

if [ "$DO_COPY" = "yes" ]; then

    python -c 'import os, sys, jinja2; sys.stdout.write(jinja2.Template(sys.stdin.read()).render(env=os.environ))' <files.jn2 >${PROVISION_TMP}/files

    # In order to avoid many concurrent ssh connections towards the same
    # server, we gather the file to copy and cluster them per server. 
    #
    # We will launch a new process, per machine, that copies the listed
    # files for that machine.
    
    # Cleaning the listings
    [ "$VERBOSE" = "yes" ] && echo "Preparing listings"
    for machine in ${MACHINES[@]}; do : > ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]}; done

    # Ignore empty lines and cluster the files per machine
    sed '/^$/d' ${PROVISION_TMP}/files | while IFS='' read -r line; do
	src=${line#*:}
	machine=${line%%:*}
	if [ -e $src ]; then
	    echo "$src" >> ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]}
	else
	    echo "\tIgnoring $src [for $machine]."
	fi
    done

    [ "$VERBOSE" = "yes" ] && echo "Copying files"
    declare -A RSYNC_PIDS
    for machine in ${MACHINES[@]}
    do
	#if [ -f ${PROVISION_TMP}/copy.$machine.${FLOATING_IPs[$machine]} ]; then
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
        #fi
    done

    # Wait for all the copying to finish
    [ "$VERBOSE" = "yes" ] && echo "Waiting for the files to be copied (${#RSYNC_PIDS[@]} background jobs)"
    for job in ${!RSYNC_PIDS[@]}; do echo -e "\t* on $job [PID: ${RSYNC_PIDS[$job]}]"; done
    FAIL=""
    for job in ${!RSYNC_PIDS[@]}
    do
	wait ${RSYNC_PIDS[$job]} || FAIL+="$job (${RSYNC_PIDS[$job]}), "
	echo -n "."
    done
    if [ -n "$FAIL" ]; then
	oups "Failed copying"
	echo "$FAIL"
	echo "Exiting..." 
	exit 1
    else
	[ "$VERBOSE" = "yes" ] && thumb_up " Files copied"
    fi
fi

########################################################################

[ "$VERBOSE" = "yes" ] && echo "Configuring servers:"
export SCRIPT_FOLDER=${MM_HOME}/scripts
export DB_SERVER=${MACHINE_IPs[openstack-controller]} # Used in the templates
declare -A PROVISION_PIDS
for machine in ${MACHINES[@]}
do
     _SCRIPT=${SCRIPT_FOLDER}/${PROVISION[$machine]}.jn2
    if [ -z "${PROVISION[$machine]}" ] || [ ! -f ${_SCRIPT} ]; then
	oups "\tProvisioning script unknown for $machine"
    else
	# It will use the (exported) environment variables
	python -c 'import os, sys, jinja2; sys.stdout.write(jinja2.Environment(loader=jinja2.FileSystemLoader(os.environ.get("SCRIPT_FOLDER")), trim_blocks=True).from_string(sys.stdin.read()).render(env=os.environ))' <${_SCRIPT} >${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]}

	ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} 'sudo bash -e -x 2>&1' <${PROVISION_TMP}/run.$machine.${FLOATING_IPs[$machine]} 1>${PROVISION_TMP}/log.$machine.${FLOATING_IPs[$machine]} &
	PROVISION_PIDS[$machine]=$!
    fi
done

# Wait for all the copying to finish
[ "$VERBOSE" = "yes" ] && echo -e "Waiting for servers to be configured (${#PROVISION_PIDS[@]} background jobs)"
declare -A PROGRESS
for job in ${!PROVISION_PIDS[@]}; do PROGRESS[$job]="\e[34m...\e[0m"; done
function print_progress {
    echo -e "\r"
    for job in ${!PROGRESS[@]}; do echo -ne "$job [ ${PROGRESS[$job]} ] "; done
}
for job in ${!PROVISION_PIDS[@]}
do
    wait ${PROVISION_PIDS[$job]} && PROGRESS[$job]="\e[32m\xE2\x9C\x93\e[0m" || PROGRESS[$job]="\e[31m\xE2\x9C\x97\e[0m"
done
# if [ -n "$FAIL" ];
#    oups "Failed configuring: $FAIL"
# [ "$VERBOSE" = "yes" ] && thumb_up " Servers configured"


# [ "$VERBOSE" = "yes" ] && echo -e "Waiting for servers to be configured (${#PROVISION_PIDS[@]} background jobs)"
# for job in ${!PROVISION_PIDS[@]}; do echo -e "\t* on $job [PID: ${PROVISION_PIDS[$job]}]"; done
# unset FAIL
# declare -A FAIL
# for job in ${!PROVISION_PIDS[@]}
# do
#     wait ${PROVISION_PIDS[$job]} || FAIL[$job]=""
#     echo -n "."
# done
# [ "$VERBOSE" = "yes" ] && thumb_up " Servers configured"
# [ -n "$FAIL" ] && echo "Failed configuring: $FAIL"
