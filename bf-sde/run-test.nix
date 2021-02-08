## Run PTF tests for a P4 program with the Tofino model in a VM.
## The resulting derivation contains the files
##
##   model.log
##     Output of tofino-model
##   switch.log
##     Output of bf_switchd
##   test.log
##     Output of PTF tests
##   passed
##     "true" if all tests passed, "false" otherwise
##
## The file "passed" can be imported as a Nix expression

{ self, p4Name, src, testDir, lib, buildEnv, vmTools, runCommand,
  procps, utillinux, getopt, fontconfig,
  bf-sde, p4-hlir, ptf-modules, ptf-utils, pythonModules ? [] }:

let
  prefix = "bf-sde-${bf-sde.version}";

  ## The test  environment is the  sde environment (as  constructed by
  ## ./sde.nix) augmented  with the  package of  the P4  program being
  ## tested.
  testEnv = buildEnv {
    name = "${prefix}-${p4Name}-test-environment";
    paths = [ bf-sde self ];
    ignoreCollisions = true;
  };

  ## bf-drivers is also required, but it is already part of the
  ## environment of the ptf command (see comments in
  ## ptf-modules/default.nix)
  python = ptf-modules.python;
  ptfModules = map (mod: python.pkgs.${mod}) pythonModules;
in vmTools.runInLinuxVM (
  runCommand "${prefix}-test-case-${p4Name}" {
    memSize = 6*1024;
    postVM = ''
      mv xchg/*.log $out
      if [ $(cat xchg/test.status) -eq 0 ]; then
        echo -en "\033[01;32m"
        echo "Test passed"
        echo "true" >$out/passed
      else
        echo -en "\033[01;31m"
        echo "Test failed"
        echo "false" >$out/passed
      fi
      echo -en "\033[0m"
    '';
  } ''
    mkdir /tmp/mock_sudo
    echo 'exec "$@"' >/tmp/mock_sudo/sudo
    chmod a+x /tmp/mock_sudo/sudo
    mkdir /mnt

    export SDE=${testEnv}
    export SDE_INSTALL=$SDE
    export P4_INSTALL=$SDE
    export PATH=/tmp/mock_sudo:${lib.strings.makeBinPath
           [ testEnv procps utillinux getopt python fontconfig ]}:$PATH
    export FONTCONFIG_FILE=${fontconfig.out}/etc/fonts/fonts.conf

    echo "============================================="
    echo "Running tests for P4 program ${p4Name}"
    echo "============================================="

    echo "Creating veth interfaces..."
    bash -e veth_setup.sh

    echo "Starting Tofino model..."
    run_tofino_model.sh -p ${p4Name} >/tmp/xchg/model.log 2>&1 &

    echo "Starting bf_switchd..."
    run_switchd.sh -p ${p4Name} -- --model >/tmp/xchg/switch.log 2>&1 &

    echo "Starting tests"
    set +e
    export PTF_PYTHONPATH=${python.pkgs.makePythonPath ptfModules}:$PYTHONPATH
    run_p4_tests.sh -p ${p4Name} -t ${src}/${testDir} 2>&1 | tee /tmp/xchg/test.log
    echo $? >/tmp/xchg/test.status
    exit 0
  '')
