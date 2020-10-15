#!/bin/bash

set -e

profile=${SDE_PROFILE:-/nix/var/nix/profiles/per-user/$USER/bf-sde}
if ! [ -e $profile ]; then
    echo -n "Please install a clone of the bf-sde-nixpkgs Git repository "
    echo  "in the profile $profile"
    exit 1
fi

nix-shell -I nixpkgs=$profile -E "with import <nixpkgs> {}; bf-sde.v@VERSION@.mkShell" ${1:+--arg inputFn "$1"}
