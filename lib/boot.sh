#!/usr/bin/env bash

# Get credentials and machines settings
source $(dirname ${BASH_SOURCE[0]})/settings.sh

PREFIX='mm'

function usage {
    echo "Usage: ${MM_CMD:-$0} [options]"
    echo -e "\noptions are"
    echo -e "\t--machines <list>,"
    echo -e "\t        -m <list>      \tA comma-separated list of machines"
    echo -e "\t                       \tDefaults to: \"${MACHINES[@]// /,}\"."
    echo -e "\t                       \tWe filter out machines that don't appear in the default list."
    echo -e "\t--prefix <name>,"
    echo -e "\t      -p <name>        \tName for each snapshot: <prefix>-<nodename>"
    echo -e "\t                       \tDefaults to '${PREFIX}'"
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
        --prefix|-p) PREFIX=$2; shift;;
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
    done
    MACHINES=(${CUSTOM_MACHINES})

    echo "Using these machines: ${CUSTOM_MACHINES// /,}"

fi

#######################################################################
# Prepare the tmp folders
for machine in ${MACHINES[@]}; do mkdir -p ${MM_TMP}/$machine/boot; done

#######################################################################
export LIB=${MM_HOME}/lib
source $LIB/utils.sh

if [ ${#MACHINES[@]} -eq 0 ]; then
    echo "Nothing to be done. Exiting..." >${ORG_FD1}
    exit 2 # or 0?
fi

#######################################################################

TENANT_ID=$(openstack project list | awk '/'${OS_TENANT_NAME}'/ {print $2}')
# Checking if the user is admin for that tenant
CHECK=$(openstack role assignment list --user ${OS_USERNAME} --role admin --project ${OS_TENANT_NAME})
if [ $? -ne 0 ] || [ -z "$CHECK" ]; then
    echo "ERROR: $CHECK"
    echo -e "\nThe user ${OS_USERNAME} does not seem to have the 'admin' role for the project ${OS_TENANT_NAME}"
    echo "Exiting..."
    exit 1
fi

MGMT_NET=$(neutron net-list --tenant_id=${TENANT_ID} | awk '/ '${OS_TENANT_NAME}-mgmt-net' /{print $2}')
DATA_NET=$(neutron net-list --tenant_id=${TENANT_ID} | awk '/ '${OS_TENANT_NAME}-data-net' /{print $2}')

#######################################################################

declare -A JOB_PIDS
function cleanup {
    echo -e "\nStopping background jobs"
    kill -9 $(jobs -p) &>/dev/null
}
trap 'cleanup' INT TERM #EXIT #HUP ERR
# Or just kill the parent. That should kill the processes in that process group
# trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

echo "Booting servers"
FAIL=0
reset_progress
print_progress
for machine in ${MACHINES[@]}
do
    { # scoping, in that current shell
	( # In a subshell

	    exec &>${MM_TMP}/$machine/boot/log
	    set -x -e # Print commands && exit if errors

	    DN=''
	    if [ ! -z "${DATA_IPs[$machine]}" ]; then
		DN="--nic net-id=$DATA_NET,v4-fixed-ip=${DATA_IPs[$1]}"
	    fi
	    # Booting a machine
	    echo -e "Booting $machine from ${PREFIX}-$machine"
	    nova boot --flavor ${FLAVORS[$machine]} --image ${PREFIX}-$machine --security-group ${OS_TENANT_NAME}-sg \
--nic net-id=${MGMT_NET},v4-fixed-ip=${MACHINE_IPs[$machine]} $DN $machine 2>&1 > /dev/null
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

########################################################################
print_progress # to have a clear picture
if (( FAIL > 0 )) ; then
    oups "\a\n${FAIL} servers failed to boot"
    exit 1
else
    thumb_up "\nBooting successful"
fi
