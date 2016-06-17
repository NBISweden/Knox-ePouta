#!/usr/bin/env bash

# Get credentials and machines settings
HERE=$(dirname ${BASH_SOURCE[0]})
source $HERE/settings.sh

export VAULT=vault

function usage {
    echo "Usage: $0 [options]"
    echo -e "\noptions are"
    echo -e "\t--machines <list>,"
    echo -e "\t        -m <list>      \tA comma-separated list of machines"
    echo -e "\t                       \tDefaults to: \"${MACHINES[@]// /,}\"."
    echo -e "\t                       \tWe filter out machines that don't appear in the default list."
    echo -e "\t--vault <name>         \tName of the drop folder in the servers"
    echo -e "\t                       \tDefaults to '${VAULT}'"
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
        --vault) VAULT=$2; shift;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

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
	echo "Nothing to be done. Exiting..."
	exit 2
    else
	[ "$VERBOSE" = "yes" ] && echo "Using these machines: ${CUSTOM_MACHINES// /,}"
    fi
fi

#######################################################################
export TL_HOME MOSLER_IMAGES
export LIB=${MM_HOME}/lib
mkdir -p ${PROVISION_TMP}
source $LIB/utils.sh

#######################################################################
source $LIB/ssh_connections.sh

#######################################################################
[ "$VERBOSE" = "yes" ] && echo "Copying files"
FAIL=0
reset_progress
print_progress
for machine in ${MACHINES[@]}
do
    { # scoping, in that current shell
	( # In a subshell

	    FOLDER=$LIB/${PROVISION[$machine]}
	    [ ! -d ${FOLDER} ] && oups "\nProvisioning folder unknown for $machine" && exit 1

	    exec &>${PROVISION_TMP}/sync-log.$machine
	    set -x -e # Print commands && exit if errors

	    # Preparing the drop folder
	    ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} mkdir -p ${VAULT}
	    
	    # Copying all files to the VAULT on that machine
	    rsync -avL -e "ssh -F ${SSH_CONFIG}" ${FOLDER}/files/ ${FLOATING_IPs[$machine]}:${VAULT}/.
	    
	    [ "$machine" == "thinlinc-master" ] && rsync -av -e "ssh -F ${SSH_CONFIG}" $TL_HOME/ ${FLOATING_IPs[$machine]}:${VAULT}/.
	    
	    if [ "$machine" == "openstack-controller" ]; then
		for img in project-computenode-stable project-loginnode-stable topolino-q-stable; do
		    rsync -av -e "ssh -F ${SSH_CONFIG}" ${MOSLER_IMAGES}/$img ${FLOATING_IPs[$machine]}:${VAULT}/.
		done
	    fi
	    
	    # Phase 2: running some commands
	    _SCRIPT=${PROVISION_TMP}/sync.$machine
	    render_template $machine ${FOLDER}/sync.jn2 ${_SCRIPT}
	    ssh -F ${SSH_CONFIG} ${FLOATING_IPs[$machine]} 'sudo bash -e -x -v 2>&1' <${_SCRIPT}
	)
	RET=$?
	if [ $RET -eq 0 ]; then report_ok $machine; else report_fail $machine; fi
	print_progress
	exit $RET
    } &
    JOB_PIDS[$machine]=$!
done
# Wait for all the copying to finish
for job in ${JOB_PIDS[@]}; do wait ${job} || ((FAIL++)); print_progress; done
print_progress # to have a clear picture
if (( FAIL > 0 )) ; then
    oups "\nFailed copying"
    #kill_notifications # already trapped
    echo "Exiting..." 
    exit 1
    # else
    # 	[ "$VERBOSE" = "yes" ] && thumb_up "\nFiles copied"
fi

#kill_notifications # already trapped
