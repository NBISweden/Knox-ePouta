 #!/usr/bin/env bash

function usage {
    echo "Usage: $0 command [options]"
    echo -e "\ncommands are:"
    echo -e "\tconnect      \tConnects via ssh into the VMs"
    echo -e "\tinit         \tInitializes the VMs"
    echo -e "\tprovision    \tConfigures the infracstructure"
    echo -e "\treset        \tRestores to the VMs to some original status"
    echo -e "\tsync         \tCopies relevant files to the VMs"

    echo -e "\nSupply --help (or -h) to see the options for each command"

    echo ""
}

case "$1" in
    init)
	TASK=$1
	export TASK
	export _CLOUD=$2
	shift; shift # Remove the command name from $@
	export MM_CMD="$0 ${TASK}-${_CLOUD}"
	$(dirname ${BASH_SOURCE[0]})/lib/${TASK}-${_CLOUD}.sh $@ # pass the remaining arguments
	;;
    sync|provision|reset|connect)
	TASK=$1
	export TASK
	shift # Remove the command name from $@
	export MM_CMD="$0 ${TASK}"
	$(dirname ${BASH_SOURCE[0]})/lib/${TASK}.sh $@ # pass the remaining arguments
	;;
    *) echo "$0: error - unrecognized command $1" 1>&2; usage; exit 1;;
esac
