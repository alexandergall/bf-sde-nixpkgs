#!/bin/bash

if [ -n "$1" ]; then
  cd $1
fi

export PATH=@_PATH@
export LD_LIBRARY_PATH=@_LD_LIBRARY_PATH@
export SDE=@RUNTIME_ENV_WITH_ARTIFACTS@
export SDE_INSTALL=$SDE
export SAL_HOME=${SAL_HOME:-@APS_BF2556_PLATFORM@}
export TP_INSTALL=@APS_BF2556_PLATFORM@
export P4_PROG=@P4_PROG@

exec @APS_BF2556_PLATFORM@/bin/salRefApp
