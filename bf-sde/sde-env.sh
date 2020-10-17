#!/bin/bash

set -e

## This script is expected to be executed from the "bin" directory of
## a Nix profile which also contains a copy of the Git repository at
## the top-level (e.g. as created by "make install").  Hence, the
## "make env" command below will use the top-level Makefile from
## that repo.

dir=$(realpath -s $(dirname $0)/..)
echo "Using Nix expression from $dir"
make -f $dir/Makefile env VERSION=v@VERSION@ INPUT_FN="$1"
