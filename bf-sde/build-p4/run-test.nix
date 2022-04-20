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

{ self, p4Name, src, testDir, lib, build, vmTools, runCommand,
  bf-sde, ptf-modules, pythonModules ? [] }:

let
  ## bf-drivers is also required, but it is already part of the
  ## environment of the ptf command (see comments in
  ## ptf-modules/default.nix)
  python = ptf-modules.python;
  ptfModules = map (mod: python.pkgs.${mod}) pythonModules;
in vmTools.runInLinuxVM (
  runCommand "bf-sde-${bf-sde.version}-test-case-${p4Name}" {
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
    ## /usr/bin/sudo is hardcoded in the run_* scripts (on purpose,
    ## see sde/tools.nix). Create a fake sudo to satisfy this.
    mkdir -p /usr/bin
    echo 'exec "$@"' >/usr/bin/sudo
    chmod a+x /usr/bin/sudo
    mkdir /mnt

    export PATH=${lib.strings.makeBinPath [ bf-sde ]}:$PATH

    echo "============================================="
    echo "Running tests for P4 program ${p4Name}"
    echo "============================================="
    echo "Starting model and bf_switchd"
    ${self}/bin/${p4Name} 1>/tmp/xchg/switch.log 2>&1 3>/tmp/xchg/model.log 4>&3 &

    ## Avoid a race with the test script"
    sleep 5

    echo "Starting tests"
    set +e
    export PTF_PYTHONPATH=${python.pkgs.makePythonPath ptfModules}:$PYTHONPATH
    run_p4_tests.sh -p ${p4Name} -t ${src}/${testDir} --arch=${self.target} \
      --test-params="base_pick_path=\"${build}/share/${self.target}pd/\"" 2>&1 | tee /tmp/xchg/test.log
    echo $? >/tmp/xchg/test.status
    exit 0
  '')
