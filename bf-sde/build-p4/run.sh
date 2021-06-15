#!/bin/bash
set -e

if [ -n "$1" ]; then
  cd $1
fi

export P4_INSTALL=@BUILD@
exec @RUNTIME_ENV@/bin/run_switchd.sh -p @EXEC_NAME@
