#!/bin/bash
set -e
config=$1
if [ -n "$TOFINO_PORT_MAP" ]; then
    jq '.p4_devices[0].p4_programs[0] += {"board-port-map": "'$TOFINO_PORT_MAP'"}' $config >$config.tmp
    mv $config.tmp $config
fi
