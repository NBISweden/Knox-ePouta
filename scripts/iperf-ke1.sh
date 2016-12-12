[knox1]$ iperf3 -4 -s # the server
[epouta1]$ iperf3 -4 -c knox1 -P 10 -t 60 # the 10 connections
