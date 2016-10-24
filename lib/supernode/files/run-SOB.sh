#!/usr/bin/env bash

[ ${BASH_VERSINFO[0]} -lt 4 ] && exit 1

ALL_COMPUTE_NODES="compute1 compute2 compute3 epouta1 epouta2 epouta3"
WORK=/mnt/projects/SOB/work
TESTS=$(dirname ${BASH_SOURCE[0]})/sob-tests

declare -a COMPUTE_NODES=()

_note=$'\e[31m\xE2\x9A\xA0\e[0m'

function usage {
    echo "Usage: $0 [arguments]"
    echo -e "\narguments are"
    echo -e "\t--compute-nodes <list>,"
    echo -e "\t             -n <list> \tA comma-separated list of 3 compute nodes only."
    echo -e "\t                       \tNote: We filter out the weirdos from that list."
    echo -e "\t                       \t$_note mandatory argument"
    echo -e "\t--working-dir <name>,"
    echo -e "\t           -w <name>   \tWorking directory. Must be an NFS share."
    echo -e "\t                       \tDefaults to '${WORK}'"
    echo -e "\t--tests <name>,"
    echo -e "\t     -t <name>         \tFile containing the SOB tests."
    echo -e "\t                       \tDefaults to '${TESTS}'"
    echo -e "\t                       \t$_note mandatory argument"
    echo -e "\t--help,-h              \tOutputs this message and exits"
    echo -e "\t-- ...                 \tAny other options appearing after the -- will be ignored"
}

# While there are arguments or '--' is reached
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0;;
        --compute-nodes|-n) COMPUTE_NODES=(${2//,/ }); shift;;
        --working-dir|-w) WORK=$2; shift;;
        --tests|-t) TESTS=$2; shift;;
        --) shift; break;;
        *) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
    esac
    shift
done

[ ! -r $TESTS ] && echo "Tests not found" && exit 1

#######################################################################
# Selecting the compute nodes
_all=${ALL_COMPUTE_NODES}
for cn in ${!COMPUTE_NODES[@]}; do
    machine=${COMPUTE_NODES[$cn]}
    if [[ "$_all" =~ "$machine" ]]
    then
	_all=${_all//$machine/} # consume it
    else
	unset COMPUTE_NODES[$cn]
    fi
done

if [ ${#COMPUTE_NODES[@]} -ne 3 ]; then
    echo "Error: You must specify a list of 3 compute nodes from this list [${ALL_COMPUTE_NODES// /,}]"
    exit 1
fi

echo "Selected Compute Nodes: [${COMPUTE_NODES[@]// /,}]"

#######################################################################
# SOB tests

declare -a SOB_TESTS=()

echo "Selected Tests in [${TESTS}]"
while read -r line; do
    [[ "$line" =~ ^#.*$ ]] && continue # skip comments
    [[ -z "$line" ]] && continue # skip empty lines
    [[ "$line" = 'sob '* ]] && SOB_TESTS+=("${line}") # starts with 'sob'
done < $TESTS

########################################################################
# Results

SOB_RESULTS=~/results/SOB/
SOB_PROGRESS=$SOB_RESULTS/progress
rm -rf $SOB_RESULTS
mkdir -p $SOB_PROGRESS

########################################################################
# Printing Progress 
declare -a MSG
MSG[0]=$'\e[34m\xE2\x80\xA6\e[0m'     # ... (ellipsis)
MSG[1]=$'\e[32m\xE2\x9C\x93\e[0m'     # ok (checkmark)
MSG[2]=$'\e[31m\xE2\x9C\x97\e[0m'     # fail (cross)

function print_progress {
    ( flock -x 200 # lock exclusively fd 200. Unlock is automatic
      printf "\e[2K\r|" # clear line and go back to the beginning
      for cn in ${COMPUTE_NODES[@]}; do printf " %s %3b |" $cn ${MSG[$(<$SOB_PROGRESS/$cn/$1)]}; done
    ) 200>$SOB_PROGRESS/lock.$1
}

function reset_progress { # Initialization
    for cn in ${COMPUTE_NODES[@]}; do echo -n 0 > $SOB_PROGRESS/$cn/$1; done
}
function report_ok { # Not testing if $1 exists. It will!
    echo -n 1 > $SOB_PROGRESS/$1/$2
}
function report_fail {
    echo -n 2 > $SOB_PROGRESS/$1/$2
}

########################################################################
# Prepare the progress and work folders
for cn in ${COMPUTE_NODES[@]}; do
    mkdir -p $SOB_PROGRESS/$cn;
    # i=${#SOB_TESTS[@]}
    # while ((i--)); do mkdir -p $WORK/${i}/${cn}; done
done

########################################################################
# Keeping track of jobs
declare -A JOB_PIDS

function cleanup {
    echo -e "\nStopping background jobs"
    #kill -9 $(jobs -p) &>/dev/null
    kill -9 ${JOB_PIDS[@]} &>/dev/null
    #exit 1
}
trap 'cleanup' INT TERM #EXIT #HUP ERR

########################################################################
# For each test... Run on all compute nodes and wait.
for i in ${!SOB_TESTS[@]}; do
    echo -e "##################"
    echo "Running SOB test: '${SOB_TESTS[$i]}'"
    FAIL=0
    JOB_PIDS=()
    reset_progress $i
    print_progress $i
    mkdir -p $SOB_RESULTS/test-${i}

    for cn in ${COMPUTE_NODES[@]}
    do
	{ # Scoping, in that current shell
	    # As the current user, who already has the ssh keys setup...
	    ssh $cn <<EOF &>$SOB_RESULTS/test-${i}/${cn}.log
function on_interrupt {
    pkill sob
    rm -rf $WORK/test-${i}/${cn}
}
trap 'on_interrupt' INT TERM #EXIT HUP ERR
set -e -x
#rm -rf $WORK/test-${i}/${cn}
mkdir -p $WORK/test-${i}/${cn}
pushd $WORK/test-${i}/${cn}
${SOB_TESTS[$i]}
popd
echo "Cleaning up"
rm -rf $WORK/test-${i}/${cn}
EOF
	    RET=$?
	    if [ $RET -eq 0 ]; then report_ok $cn $i; else report_fail $cn $i; fi
	    print_progress $i
	    exit $RET
	} &
	JOB_PIDS[$cn]=$!
    done

    # Wait for all jobs
    for job in ${!JOB_PIDS[@]}; do wait ${JOB_PIDS[$job]} && unset JOB_PIDS[$job] || ((FAIL++)); done

    # Success or not?
    print_progress $i
    echo -en "\nResult: "
    if (( FAIL > 0 )); then
	echo -e "\a${FAIL} failures"
    else 
	echo "success"

	# Print results
	for cn in ${COMPUTE_NODES[@]}
	do
	    echo "* On ${cn}:"
	    grep 'Wrote ' $SOB_RESULTS/test-${i}/${cn}.log
	    grep 'Read ' $SOB_RESULTS/test-${i}/${cn}.log
	done

    fi

done
