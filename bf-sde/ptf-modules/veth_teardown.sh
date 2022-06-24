#!/bin/bash

if [ -r "$TOFINO_MODEL_PORTINFO" ]; then
    @PTF_UTILS@/bin/veth_from_portinfo --teardown $TOFINO_MODEL_PORTINFO
else
    @PTF_UTILS@/bin/veth_teardown_orig.sh "$@"
fi
