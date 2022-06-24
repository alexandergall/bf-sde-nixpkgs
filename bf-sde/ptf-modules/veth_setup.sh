#!/bin/bash

if [ -r "$TOFINO_MODEL_PORTINFO" ]; then
    @PTF_UTILS@/bin/veth_from_portinfo $TOFINO_MODEL_PORTINFO
else
    @PTF_UTILS@/bin/veth_setup_orig.sh "$@"
fi
