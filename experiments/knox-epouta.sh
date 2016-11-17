 #!/usr/bin/env bash

function usage {
    echo "Usage: $0 command [options]"
    echo -e "\ncommands are:"
    echo -e "\tconnect      \tConnects via ssh into the VMs"
    echo -e "\tinit <cloud> \tInitializes the VMs in <cloud>"
    echo -e "\tprovision    \tConfigures the infracstructure"
    echo -e "\treset        \tRestores to the VMs to some original status"
    echo -e "\tsync         \tCopies relevant files to the VMs"

    echo -e "\nSupply --help (or -h) to see the options for each command"

    echo ""
}

export KE_TASK=$1
export KE_CMD="$0 ${KE_TASK}"
_SCRIPT=$(dirname ${BASH_SOURCE[0]})/lib/${KE_TASK}.sh

case "${KE_TASK}" in
    init)
	export KE_CLOUD=$2
	shift; shift # Remove the 2 first arguments from $@
	${_SCRIPT} --cloud ${KE_CLOUD} $@ # pass the remaining arguments
	;;
    sync|provision|reset|connect)
	shift # Remove the task from $@
	${_SCRIPT} $@ # pass the remaining arguments
	;;
    *) echo "$0: error - unrecognized command $1" 1>&2; usage; exit 1;;
esac
