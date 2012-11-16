#!/bin/sh
Pa=ebin
cmNode=$1
CMErlCmd=""

if [ $# == 2 ]; then
     cmNode=$2
     if [ $1 == $2 ]; then
         CMErlCmd="erl -name CM@$2 -pa $Pa -setcookie imem -kernel inet_dist_listen_min 9000 inet_dist_listen_max 9020"
     fi
 else
     echo "Starting CM on same machine"
     CMErlCmd="erl -name CM@$1 -pa $Pa -setcookie imem -kernel inet_dist_listen_min 9000 inet_dist_listen_max 9020"
 fi

echo "CM on $cmNode"

Opts="-pa deps/*/ebin -setcookie imem -env ERL_MAX_ETS_TABLES 10000 -kernel inet_dist_listen_min 9000 inet_dist_listen_max 9020 -eval \"apply(net_adm, ping, ['CM@$cmNode'])\" -s imem start -imem start_monitor true"

gnome-terminal \
    --tab -e "$CMErlCmd" \
    --tab -e "erl -name A@$1 -pa $Pa $Opts -imem node_type disc" \
    --tab -e "erl -name B@$1 -pa $Pa $Opts -imem node_type disc" \
    --tab -e "erl -name C@$1 -pa $Pa $Opts -imem node_type disc" \
    --tab -e "erl -name D@$1 -pa $Pa $Opts -imem node_type ram" \
    &