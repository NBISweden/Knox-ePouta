########################################################################
# Finding a suitable port for the notification server
NOTIFICATION_PORT=${PORT}
while fuser ${NOTIFICATION_PORT}/tcp &>/dev/null ; do (( NOTIFICATION_PORT++ )); done
NOTIFICATION_URL=http://${PHONE_HOME}:${NOTIFICATION_PORT}

function kill_notifications {
    [ "$VERBOSE" = "yes" ] && echo -e "\nStopping the notification server"
    fuser -k ${NOTIFICATION_PORT}/tcp &>/dev/null
    #kill -9 ${NOTIFICATION_PID}
}

# Cleaning up after us. Catching EXIT is enough. Even on errors
trap "kill_notifications" EXIT #INT TERM ERR 

[ "$VERBOSE" = "yes" ] && echo "Starting the notification server [on port ${NOTIFICATION_PORT}]"
python $LIB/notifications.py ${NOTIFICATION_PORT} "${MACHINES[@]}" &> ${PROVISION_TMP}/notifications.log &
NOTIFICATION_PID=$!
sleep 1

########################################################################
# Finding a suitable port for the notification server

function thumb_up {
    [ -n "$1" ] && echo -ne "$1 "
    echo -e "\xF0\x9F\x91\x8D"
}
function oups {
    [ -n "$1" ] && echo -ne "$1 "
    echo -e "\e[31m\xF0\x9F\x9A\xAB\e[0m"
}

function print_progress {
    ans=$(curl ${NOTIFICATION_URL}/show_progress 2>/dev/null) # silence the progress bar
    echo -ne "\r$ans"
}

function reset_progress { # Initialization
    for m in ${MACHINES[@]}; do
	curl -X POST -d '\e[34m...\e[0m' ${NOTIFICATION_URL}/progress/$m &>/dev/null 
    done
}
# Not testing if $1 exists. It will!
function report_ok {
    curl -X POST -d ' \e[32m\xE2\x9C\x93\e[0m ' ${NOTIFICATION_URL}/progress/$1 &>/dev/null 
}
function report_fail {
    curl -X POST -d ' \e[31m\xE2\x9C\x97\e[0m ' ${NOTIFICATION_URL}/progress/$1 &>/dev/null
    curl -X POST ${NOTIFICATION_URL}/fail/$1 &>/dev/null
}
function filter_out {
    curl -X POST -d ' \e[31m\xF0\x9F\x9A\xAB\e[0m ' ${NOTIFICATION_URL}/progress/${MACHINES[$1]} &>/dev/null 
    unset MACHINES[$1]
}

function filter_out_machine {
    for i in ${!MACHINES[@]}; do
	[ ${MACHINES[$i]} == $1 ] && filter_out $i && return 0 # Found, removed and done!
    done
    return 1 # not found
}


########################################################################
# For the parallel execution
########################################################################

declare -A JOB_PIDS
# function kill_bg_jobs {
#     [ "$VERBOSE" = "yes" ] && echo -e "\nStopping background jobs"
#     for job in ${JOB_PIDS[@]}; do kill -9 $job &>/dev/null; done
# }
function cleanup {
    [ "$VERBOSE" = "yes" ] && echo -e "\nStopping background jobs"
    kill -9 $(jobs -p) &>/dev/null
    #kill_notifications
}
#set -e # exit if errors
# Cleaning up after us. Catching EXIT is enough. Even on errors
# shopt -qs huponexit
trap 'cleanup' INT TERM #EXIT #HUP ERR

# Or just kill the parent. That should kill the processes in that process group
# trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT


########################################################################
# Finding a suitable port for the notification server
function preamble {
    [ $# -ne 2 ] && return 1
    local _script=$1
    local machine=$2
    cat > $_script <<EOF
#!/usr/bin/env bash

function register {
    curl -X POST -d \$2 ${NOTIFICATION_URL}/$machine/\$1 2>/dev/null
}

function wait_for {
    local -r -i timeout=\${4:-30} # default: 30 seconds, well...if you don't count the backoff...
    local -i t=0 # local integer variable
    local -i backoff=1

    while (( (t++) <= timeout )) ; do
	echo -e "Try \$t \\tTimeout: \$timeout"
        res=\$(curl ${NOTIFICATION_URL}/\$1/\$2 2>/dev/null)
        if [ \$? -ne 0 ] ; then echo "Unable to get status for \$2 on \$1"; break; fi
        if [ "\$res" == "\$3" ] ; then echo "Task \$2 is \$3 on \$1 (after \$t seconds)"; return 0; fi
        if [ "\$res" == "ERR" ] ; then echo "Task \$2 failed on \$1: Exiting..."; break; fi
	sleep \$backoff
        if (( (t % 10) == 0 )); then
	    backoff=\$(( backoff * 2 ))
            echo "new backoff: \$backoff"
	fi
    done
    exit 1
}

# -w doesn't work on nc
function wait_port {
    local -r -i timeout=\${3:-30} # default: 30 seconds, well...if you don't count the backoff...
    local -i t=0 # local integer variable
    local -i backoff=1
    while (( (t++) <= timeout )) ; do
	echo -e "Try \$t \\tTimeout: \$timeout"
	nc -4 -z -v \$1 \$2 && return 0
        res=\$(curl ${NOTIFICATION_URL}/fail/\$1 2>/dev/null)
        if [ \$? -ne 0 ] ; then echo "Unable to get contact to \$1"; break; fi
        if [ "\$res" == "FAIL" ] ; then echo "\$1 has already failed: Giving up here..."; break; fi
	sleep \$backoff
        if (( (t % 10) == 0 )); then
	    backoff=\$(( backoff * 2 ))
            echo "new backoff: \$backoff"
	fi
    done
    exit 1
}
EOF
}

########################################################################
# Rendering the templates
########################################################################
function render_template {
    # $1 : machine
    # $2 : template
    # $3 : script
    
    preamble $3 $1 # Common functions for notifications
    python -c "import os, sys, jinja2; \
               sys.stdout.write(jinja2.Environment( loader=jinja2.FileSystemLoader(os.environ.get('LIB')) ) \
                         .from_string(sys.stdin.read()) \
                         .render(env=os.environ))" \ <$2 >>$3
}
