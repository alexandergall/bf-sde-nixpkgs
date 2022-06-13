#!/bin/bash

set -e

origPath=$PATH
PATH=@PATH@
sdeNixexpr=@SDE_NIXEXPR@
version=v$(echo @VERSION@ | sed -e 's/\./_/g')
export NIX_PATH=

self=$(basename $0)

usage () {
    echo "usage: $self [--help] [--pure] [--platform=<platform>] [--pkgs=<pkg>,...] [--python-modules=<module>,...] [--python-ptf-modules=<module>,...]"
    exit 0
}

opts=$(getopt -l platform: \
              -l pkgs: \
              -l python-modules: \
              -l python-ptf-modules: \
	      -l pure \
              -l help \
              -o "" \
              -n $self \
              -- "$@")
[ $? -eq 0 ] || usage

eval set -- $opts

while [ $# -gt 0 ]; do
    case "$1" in
        --platform)
            platform=$2
            shift 2
            ;;
        --pkgs)
            oIFS=$IFS
            IFS=,
            pkgs=($2)
	    IFS=$oIFS
            shift 2
            ;;
        --python-modules)
            oIFS=$IFS
            IFS=,
            pythonModules=($2)
	    IFS=$oIFS
            shift 2
            ;;
        --python-ptf-modules)
            oIFS=$IFS
            IFS=,
            pythonPtfModules=($2)
	    IFS=$oIFS
            shift 2
            ;;
	--pure)
	    pureMode="--pure"
	    shift
	    ;;
        --help)
            usage
            ;;
        *)
            break
            ;;
    esac
done
[ $# -eq 1 ] || usage

if [ -z "$platform" -a -f /etc/machine.conf ]; then
    . /etc/machine.conf
    platform=$onie_machine
fi

if [ -z "$platform" ]; then
    echo "Can't determine platform from /etc/machine.conf, using Tofino model"
    platform=model
fi

read -r -d '' verifyFn <<-EOF || true
  with builtins;
  let
    pkgs = import $sdeNixexpr {};
    chkPkgs = {
      type = "Package";
      attrs = pkgs;
      list = pkgs.lib.splitString " " "${pkgs[@]}";
    };
    chkModules = {
      type = "Python module";
      attrs = pkgs.bf-sde.${version}.pkgs.bf-drivers.pythonModule.pkgs;
      list = pkgs.lib.splitString " " ("${pythonModules[@]}" + " ${pythonPtfModules[@]}");
    };
    check = type: set: attr:
      assert pkgs.lib.assertMsg (stringLength attr == 0 || hasAttr attr set) "\${type} \${attr} does not exist";
      set;
    checkOne = spec:
      foldl' (check spec.type) spec.attrs spec.list;
  in foldl' (prev: next: next) null (map checkOne [ chkPkgs chkModules ])
EOF
nix-instantiate --eval -E "($verifyFn)" >/dev/null

INPUT_FN="{ pkgs, pythonPkgs }: { \
             pkgs = with pkgs; [ ${pkgs[@]} ]; \
             cpModules = with pythonPkgs; [ ${pythonModules[@]} ]; \
             ptfModules = with pythonPkgs; [ ${pythonPtfModules[@]} ]; }"
if [[ ! $platform =~ ^model.* ]]; then
    kernelArg="--argstr kernelRelease $(uname -r)"
fi
PATH=$origPath
nix-shell -j auto $pureMode -I nixpkgs=$sdeNixexpr -E "with import <nixpkgs> {}; bf-sde.${version}.mkShell" \
          $kernelArg --argstr platform $platform \
          --arg inputFn "$INPUT_FN"
