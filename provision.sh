#!/usr/bin/env bash

# Get credentials and machines settings
HERE=$(dirname ${BASH_SOURCE[0]})
source $HERE/settings.sh

export TL_HOME MOSLER_HOME MOSLER_MISC MOSLER_IMAGES
export LIB=${MM_HOME}/lib

export VAULT=vault
export CONNECTION_TIMEOUT=1 #seconds
DO_COPY=yes
export FAST=false

function usage {
    echo "Usage: $0 [options]"
    echo -e "\noptions are"
    echo -e "\t--machines <list>,"
    echo -e "\t        -m <list>      \tA comma-separated list of machines"
    echo -e "\t                       \tDefaults to: \"${MACHINES[@]// /,}\"."
    echo -e "\t                       \tWe filter out machines that don't appear in the default list."
    echo -e "\t--vault <name>         \tName of the drop folder in the servers"
    echo -e "\t                       \tDefaults to '${VAULT}'"
    echo -e "\t--no-copy,-n           \tSkips the steps of syncing files to the servers"
    echo -e "\t--timeout <seconds>,   \tSkips the steps of syncing files to the servers"
    echo -e "\t       -t <seconds>    \tSkips the steps of syncing files to the servers"
    echo -e "\t--fast                 \tUses tricks to provision machines faster (like mysql pre-dumps)"
    echo -e "\t--quiet,-q             \tRemoves the verbose output"
    echo -e "\t--help,-h              \tOutputs this message and exits"
    echo -e "\t-- ...                 \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) VERBOSE=no;;
        --help|-h) usage; exit 0;;
        --machines|-m) CUSTOM_MACHINES=$2; shift;;
        --no-copy|-n) DO_COPY=no;;
        --fast) FAST=true;;
        --vault) VAULT=$2; shift;;
        --timeout|-t) CONNECTION_TIMEOUT=$2; shift;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

#######################################################################
function thumb_up {
    [ -n "$1" ] && echo -e "$1 \xF0\x9F\x91\x8D"
}
function oups {
    [ -n "$1" ] && echo -e "$1 \e[31m\xF0\x9F\x9A\xAB\e[0m"
}

#######################################################################
# Logic to allow the user to specify some machines
if [ -n ${CUSTOM_MACHINES:-''} ]; then
    CUSTOM_MACHINES_TMP=${CUSTOM_MACHINES//,/ } # replace all commas with space
    CUSTOM_MACHINES="" # Filtering the ones which don't exist in settings.sh
    for cm in $CUSTOM_MACHINES_TMP; do
	if [[ "${MACHINES[@]}" =~ "$cm" ]]; then
	    CUSTOM_MACHINES+="$cm "
	else
	    echo "Unknown machine: $cm"
	fi
	# for m in ${MACHINES[@]}; do
	#     [ "$cm" = "$m" ] && CUSTOM_MACHINES+=" $cm" && break
	# done
    done
    MACHINES=(${CUSTOM_MACHINES})

    if [ ${#MACHINES[@]} -eq 0 ]; then
	oups "Nothing to be done. Exiting..."
	exit 2
    else
	[ "$VERBOSE" = "yes" ] && echo "Using these machines: ${CUSTOM_MACHINES// /,}"
    fi
fi

mkdir -p ${PROVISION_TMP}
########################################################################
# Finding a suitable port for the notification server
NOTIFICATION_PORT=${PORT}
while fuser ${NOTIFICATION_PORT}/tcp &>/dev/null ; do (( NOTIFICATION_PORT++ )); done

function kill_notifications {
    [ "$VERBOSE" = "yes" ] && echo "Stopping the notification server"
    fuser -k ${NOTIFICATION_PORT}/tcp &>/dev/null
    #kill -9 ${NOTIFICATION_PID}
}

[ "$VERBOSE" = "yes" ] && echo "Starting the notification server [on port ${NOTIFICATION_PORT}]"
python $LIB/notifications.py ${NOTIFICATION_PORT} "${MACHINES[@]}" &> ${PROVISION_TMP}/notifications.log &
NOTIFICATION_PID=$!
sleep 1

#######################################################################
# Logic to print progress and start/pause
PROGRESS_FAIL=0

function print_progress {
    ans=$(curl http://${PHONE_HOME}:${NOTIFICATION_PORT}/progress 2>/dev/null) # silence the progress bar
    echo -ne "\r$ans"
}

function reset_progress { # Initialization
    PROGRESS_FAIL=0
    for m in ${MACHINES[@]}; do
	curl -X POST -d '\e[34m...\e[0m' http://${PHONE_HOME}:${NOTIFICATION_PORT}/$m/progress &>/dev/null 
    done
}
# Not testing if $1 exists. It will!
function report_ok {
    curl -X POST -d ' \e[32m\xE2\x9C\x93\e[0m ' http://${PHONE_HOME}:${NOTIFICATION_PORT}/$1/progress &>/dev/null 
}
function report_fail {
    curl -X POST -d ' \e[31m\xE2\x9C\x97\e[0m ' http://${PHONE_HOME}:${NOTIFICATION_PORT}/$1/progress &>/dev/null
    (( PROGRESS_FAIL++ ))
}
function filter_out {
    curl -X POST -d ' \e[31m\xF0\x9F\x9A\xAB\e[0m ' http://${PHONE_HOME}:${NOTIFICATION_PORT}/${MACHINES[$1]}/progress &>/dev/null 
    unset MACHINES[$1]
}

function filter_out_machine {
    for i in ${!MACHINES[@]}; do
	[ ${MACHINES[$i]} == $1 ] && filter_out $i && return 0 # Found, removed and done!
    done
    return 1 # not found
}

#######################################################################
# Checking if machines are available
# Filtering them out otherwise
#######################################################################

SSH_CONFIG=${PROVISION_TMP}/ssh_config.${OS_TENANT_NAME}
SSH_KNOWN_HOSTS=${PROVISION_TMP}/ssh_known_hosts.${OS_TENANT_NAME}

[ "$VERBOSE" = "yes" ] && echo -e "Checking the connections:"
reset_progress
FAIL=""
cat > ${SSH_CONFIG} <<ENDSSHCFG
Host ${FLOATING_CIDR%0/24}*
	User centos
	ControlMaster auto
	ControlPersist 60s
	StrictHostKeyChecking no
	UserKnownHostsFile ${SSH_KNOWN_HOSTS}
	ForwardAgent yes
ENDSSHCFG

:> ${SSH_KNOWN_HOSTS}
for i in ${!MACHINES[@]}; do
    # python -c "import socket; \
    #            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); \
    #            s.settimeout(${CONNECTION_TIMEOUT}.0); \
    #            s.connect(('${FLOATING_IPs[${MACHINES[$i]}]}', 22))" &> /dev/null \
    nc -4 -z -w ${CONNECTION_TIMEOUT} ${FLOATING_IPs[${MACHINES[$i]}]} 22 \
	&& report_ok ${MACHINES[$i]} \
	    || { FAIL+=" ${MACHINES[$i]}"; filter_out $i; }
    print_progress
done
for machine in ${MACHINES[@]}; do ssh-keyscan -4 -T 1 ${FLOATING_IPs[$machine]} >> ${SSH_KNOWN_HOSTS} 2>/dev/null; done
#Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.
# The exit status of ssh-keyscan is 0 even when the connection failed: Using nc instead.

if [ -n "$FAIL" ]; then
    oups "\nFiltering out:$FAIL"
else
    thumb_up "\nAll connections are ready"
fi

########################################################################
# For the parallel execution
########################################################################
#set -e # exit if errors

declare -A JOB_PIDS
# function kill_bg_jobs {
#     [ "$VERBOSE" = "yes" ] && echo -e "\nStopping background jobs"
#     for job in ${JOB_PIDS[@]}; do kill -9 $job &>/dev/null; done
# }
# trap "kill_bg_jobs" ERR

# Cleaning up after us. Catching EXIT is enough. Even on errors
# shopt -qs huponexit
# trap 'echo killing bg jobs; kill $(jobs -p) &>/dev/null' HUP #INT TERM ERR 
# trap 'echo; kill_notifications || true; kill $(jobs -p); exit 1' INT ERR #TERM EXIT 
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

########################################################################
# Copying files
########################################################################
    
if [ "$DO_COPY" = "yes" ]; then

    export CONFIGS=${MM_HOME}/configs

    python -c "import os, sys, jinja2; \
               sys.stdout.write(jinja2.Template(sys.stdin.read()).render(env=os.environ))" \
	   <${LIB}/files.jn2 \
	   >${PROVISION_TMP}/files

    # In order to avoid many concurrent ssh connections towards the same
    # server, we gather the file to copy and cluster them per server. 
    #
    # We will launch a new process, per machine, that copies the listed
    # files for that machine.
    
    # Cleaning the listings
    [ "$VERBOSE" = "yes" ] && echo "Preparing listings"
    for machine in ${MACHINES[@]}; do : > ${PROVISION_TMP}/copy.$machine; done

    # Ignore empty lines and cluster the files per machine
    sed '/^$/d' ${PROVISION_TMP}/files | while IFS='' read -r line; do
	src=${line#*:}
	machine=${line%%:*}
	if [ -e $src ]; then
	    echo "$src" >> ${PROVISION_TMP}/copy.$machine
	else
	    echo -e "\tIgnoring $src [for $machine]."
	fi
    done

    [ "$VERBOSE" = "yes" ] && echo "Copying files"
    reset_progress
    print_progress
    for machine in ${MACHINES[@]}
    do
	{ 
	    ( # scoping 
		exec &>${PROVISION_TMP}/rsync.$machine
		set -x -e # Print commands && exit if errors
		# Preparing the drop folder
		ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} mkdir -p ${VAULT}
		# Copying all files to the VAULT on that machine
		while read -r f ; do
		    rsync -av -e "ssh -F ${SSH_CONFIG}" $f ${FLOATING_IPs[$machine]}:${VAULT}/.
		done < ${PROVISION_TMP}/copy.$machine
	    ) && report_ok $machine || report_fail $machine
	    print_progress
	} &
	JOB_PIDS[$machine]=$!
    done
    # Wait for all the copying to finish
    for job in ${JOB_PIDS[@]}; do wait ${job}; print_progress; done
    print_progress # to have a clear picture
    if (( PROGRESS_FAIL > 0 )) ; then
	oups "\nFailed copying"
	echo "Exiting..." 
	kill_notifications
	exit 1
    else
	[ "$VERBOSE" = "yes" ] && thumb_up "\nFiles copied"
    fi
fi

#######################################################################
# Aaaaannnnnddd...... cue music!
########################################################################
[ "$VERBOSE" = "yes" ] && echo -e "Configuring servers:"
reset_progress
print_progress
export DB_SERVER=${MACHINE_IPs[openstack-controller]} # Used in the templates
for machine in ${MACHINES[@]}
do
    # Selecting the template
     _TEMPLATE=${LIB}/${PROVISION[$machine]}.jn2
    if [ -z "${PROVISION[$machine]}" ] || [ ! -f ${_SCRIPT} ]; then
	oups "\tProvisioning script unknown for $machine"
	filter_out_machine $machine
    else

	_SCRIPT=${PROVISION_TMP}/run.$machine
	_LOG=${PROVISION_TMP}/log.$machine
	# Common functions for notifications
	cat > ${_SCRIPT} <<EOF
#!/usr/bin/env bash

function register {
    curl -X POST -d \$2 http://${PHONE_HOME}:${NOTIFICATION_PORT}/$machine/\$1
}

function wait_for {
    local _URL=http://${PHONE_HOME}:${NOTIFICATION_PORT}/\$1/\$2
    local timeout=\${4:-30} # default: 30 seconds
    local t=0
    while : ; do
        res=\$(curl \$_URL)
        if [ "\$res" = "$3" ] ; then break; fi
        if (( t >= timeout )) ; then echo "WAIT FOR \$1 to be ready with \$2: Timeout (\$timeout seconds)"; exit 1; fi # Timeout
        sleep 1
        (( t++ ))
    done
}

# -w doesn't work on nc
function wait_port {
    timeout=\${3:-30}
    t=0
    while : ; do
	#nc -4 -z \$1 \$2 &>/dev/null && break; # return 0
	nc -4 -z -v \$1 \$2 && break; # return 0
	if (( t >= timeout )) ; then exit 1; fi # Use return 1, if you don't want to also drop the shell
	sleep 1
	(( t++ ))
	echo -n "."
    done
}
EOF

	# Rendering the template
	# It will use the (exported) environment variables
	python -c "import os, sys, jinja2; \
            sys.stdout.write(jinja2.Environment(loader=jinja2.FileSystemLoader(os.environ.get('LIB'))).from_string(sys.stdin.read()).render(env=os.environ))" \
	       <${_TEMPLATE} \
	       >> ${_SCRIPT}

	{
	    ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} 'sudo bash -e -x 2>&1' <${_SCRIPT} &>${_LOG} \
		&& report_ok $machine || report_fail $machine
	    print_progress
	} &
	JOB_PIDS[$machine]=$!
    fi
done
    
for job in ${JOB_PIDS[@]}; do wait $job; print_progress; done
print_progress

if (( PROGRESS_FAIL > 0 )); then
    oups "\a\n${PROGRESS_FAIL} servers failed to be configured"
else
    [ "$VERBOSE" = "yes" ] && thumb_up "\nServers configured"
fi

kill_notifications
