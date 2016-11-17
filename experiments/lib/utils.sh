########################################################################
# Checking the global task
TASK=$1
[ -z $TASK ] && echo "Task not set: Aborting..." && exit 1

########################################################################
declare -a MSG
MSG[0]=$'\e[34m\xE2\x80\xA6\e[0m'     # ... (ellipsis)
MSG[1]=$'\e[32m\xE2\x9C\x93\e[0m'     # ok (checkmark)
MSG[2]=$'\e[31m\xE2\x9C\x97\e[0m'     # fail (cross)
MSG[3]=$'\e[31m\xF0\x9F\x9A\xAB\e[0m' # filtered (forbidden sign)
MSG[4]=$'\xF0\x9F\x91\x8D'            # success (thumb up)
########################################################################

# Used in the print_progress so that we show the filtered ones too
ALL_MACHINES=("${MACHINES[@]}")

# Prepare the tmp folders
for machine in ${MACHINES[@]}; do mkdir -p ${KE_TMP}/$machine/$TASK; done

function thumb_up {
    [ -n "$1" ] && echo -ne "$1 "
    echo -e ${MSG[4]}
}
function oups {
    [ -n "$1" ] && echo -ne "$1 "
    echo -e ${MSG[3]}
}

function print_progress {
    ( flock -x 200 # lock exclusively fd 200. Unlock is automatic
      printf "\e[2K\r|" # clear line and go back to the beginning
      for machine in ${ALL_MACHINES[@]}; do printf " %s %3b |" $machine ${MSG[$(<${KE_TMP}/$machine/$TASK/progress)]}; done
    ) 200>${KE_TMP}/lock.$TASK
}

function reset_progress { # Initialization
    for machine in ${MACHINES[@]}; do echo -n 0 > ${KE_TMP}/$machine/$TASK/progress; done
}
function report_ok { # Not testing if $1 exists. It will!
    echo -n 1 > ${KE_TMP}/$1/$TASK/progress
}
function report_fail {
    echo -n 2 > ${KE_TMP}/$1/$TASK/progress
    #curl -X POST ${NOTIFICATION_URL}/fail/$1 &>/dev/null
}
function filter_out {
    echo -n 3 > ${KE_TMP}/${MACHINES[$1]}/$TASK/progress
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
function check_connections {
    echo -e "Checking the connections:"
    reset_progress
    local CONNECTION_FAIL=""

    for i in ${!MACHINES[@]}; do
        nc -4 -z -w ${CONNECTION_TIMEOUT:-1} ${MACHINE_IPs[${MACHINES[$i]}]} 22 \
	    && report_ok ${MACHINES[$i]} \
		|| { CONNECTION_FAIL+=" ${MACHINES[$i]}"; filter_out $i; }
	print_progress
    done
    # The exit status of ssh-keyscan is 0 even when the connection failed: Using nc instead.

    echo "" # new line
    [ -n "$CONNECTION_FAIL" ] && echo "Filtering out:$CONNECTION_FAIL"

    :> ${SSH_KNOWN_HOSTS}
    for machine in ${MACHINES[@]}
    do
	ssh-keyscan -4 -T 1 ${MACHINE_IPs[$machine]} >> ${SSH_KNOWN_HOSTS} 2>/dev/null
    done
    #Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.
}


