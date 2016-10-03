# Must be included after utils.sh
#type report_ok 2>/dev/null || exit 1

#######################################################################
# Checking if machines are available
# Filtering them out otherwise
#######################################################################
echo -e "Checking the connections:"
reset_progress
CONNECTION_FAIL=""

for i in ${!MACHINES[@]}; do
    $MM_CONNECT nc -4 -z -w ${CONNECTION_TIMEOUT:-1} ${MACHINE_IPs[${MACHINES[$i]}]} 22 \
	&& report_ok ${MACHINES[$i]} \
	    || { CONNECTION_FAIL+=" ${MACHINES[$i]}"; filter_out $i; }
    print_progress
done
# The exit status of ssh-keyscan is 0 even when the connection failed: Using nc instead.

:> ${SSH_KNOWN_HOSTS}
for machine in ${MACHINES[@]}
do
    sed -i "/${MACHINE_IPs[$machine]}/ d" ${SSH_KNOWN_HOSTS}
    $MM_CONNECT ssh-keyscan -4 -T 1 ${MACHINE_IPs[$machine]} >> ${SSH_KNOWN_HOSTS} 2>/dev/null
done
#Note: I silence the errors from stderr (2) to /dev/null. Don't send them to &1.

echo "" # new line
[ -n "$CONNECTION_FAIL" ] && echo "Filtering out:$CONNECTION_FAIL"
