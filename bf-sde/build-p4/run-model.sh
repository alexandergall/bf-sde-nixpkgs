#!/bin/bash
set -e

if [ -n "$1" ]; then
  cd $1
fi

echo "Running on Tofino model"
echo "Redirect file descriptors 3/4 to isolate stdout/stderr of the Tofino model process"

redirect () {
    mode=$1
    for fd in 1 2; do
        fdn=$(($fd + 2))
        fds=$(($fd + 4))
        if [ -e /proc/$$/fd/$fdn ]; then
            if [ $mode = save ]; then
                eval "exec $fds>&$fd $fd>&$fdn"
            else
                eval "exec $fd>&$fds $fds>&-"
            fi
        fi
    done
}

cleanup () {
    /usr/bin/sudo @pkill@ tofino-model
    wait
    @sleep@ 2
    echo "Deleting veth interfaces..."
    /usr/bin/sudo --preserve-env=TOFINO_MODEL_PORTINFO @bash@ -e @RUNTIME_ENV@/bin/veth_teardown.sh
}

trap cleanup EXIT INT TERM

echo "Creating veth interfaces..."
/usr/bin/sudo --preserve-env=TOFINO_MODEL_PORTINFO @bash@ -e @RUNTIME_ENV@/bin/veth_setup.sh

## bf_switchd segfaults if run in MODEL mode and a kernel module is
## loaded
for mod in bf_kdrv bf_knet bf_kpkt; do
    /usr/bin/sudo @rmmod@ $mod 2>/dev/null || true
done

export P4_INSTALL=@BUILD@
echo "Starting Tofino model..."
if [ -r "$TOFINO_MODEL_PORTINFO" ]; then
    portinfo_option="-f $TOFINO_MODEL_PORTINFO"
fi
redirect save
@RUNTIME_ENV@/bin/run_tofino_model.sh -p @EXEC_NAME@ --arch=@ARCH@ $portinfo_option &
redirect restore

@RUNTIME_ENV@/bin/run_switchd.sh -p @EXEC_NAME@ --arch=@ARCH@
