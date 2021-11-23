#!/bin/bash

if [ -n "$1" ]; then
  cd $1
fi

export PATH=@_PATH@
export LD_LIBRARY_PATH=@_LD_LIBRARY_PATH@
export SDE=@RUNTIME_ENV_WITH_ARTIFACTS@
export SDE_INSTALL=$SDE
export SAL_HOME=${SAL_HOME:-@APS_SAL_REFAPP@}
export P4_PROG=@P4_PROG@

exec @APS_SAL_REFAPP@/bin/salRefApp
