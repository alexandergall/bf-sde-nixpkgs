{ bf-sde, pkgs, isModel }:

{ inputFn ? { pkgs, pythonPkgs }: {}, kernelID ? null,
  kernelRelease ? null, platform ? "model", runCommand ? "" }:

let
  baseboard = bf-sde.baseboardForPlatform platform;
  bspLess = baseboard == null;
  sde = bf-sde.override {
    inherit baseboard;
  };
  kernelModules = pkgs.lib.optional (! isModel platform)
    (assert kernelID != null -> kernelRelease == null;
      if kernelID != null then
        sde.pkgs.kernel-modules.${kernelID}
      else
        sde.modulesForKernel kernelRelease);
  bf-drivers = sde.pkgs.bf-drivers;
  python = bf-drivers.pythonModule;
  defaultInputs = {
    pkgs = [];
    ptfPkgs = [];
    cpModules = [];
    ptfModules = [];
  };
  inputs = defaultInputs // (builtins.tryEval inputFn).value {
    inherit pkgs;
    pythonPkgs = python.pkgs;
  };
  pythonEnv = python.withPackages (ps: [ bf-drivers ]
                                       ++ inputs.cpModules);
  greetings = rec {
    asic = ''
      Load/unload kernel modules: $ sudo \$(type -p bf_{kdrv,kpkt,knet}_mod_{load,unload})

      Compile: $ p4_build.sh <p4name>.p4
      Run:     $ run_switchd.sh -p <p4name>
    '';
    accton_as9516_32d = asic + ''
      Load/unload FPGA I2C kernel module: $ sudo \$(type -p bf_fpga_mod_{load,unload})
    '';
    model = ''
      Compile: $ p4_build.sh <p4name>.p4
      Run:     $ run_switchd.sh -p <p4name>
      Run Tofino model:
               $ sudo \$(type -p veth_setup.sh)
               $ run_tofino_model.sh -p <p4name>
               $ run_switchd.sh -p <p4name>
               $ sudo \$(type -p veth_teardown.sh)
      Run Tofino model with custom portinfo file:
               $ sudo \$(type -p veth_from_portinfo) <portinfo-file>
               $ run_tofino_model.sh -p <p4name> -f <portinfo-file>
               $ run_switchd.sh -p <p4name>
               $ sudo \$(type -p veth_from_portinfo) --teardown <portinfo-file>
      Run PTF tests: run the Tofino model, then
               $ run_p4_tests.sh -p <p4name> -t <path-to-dir-with-test-scripts>
    '';
    modelT2 = model;
    modelT3 = model;
  };
in pkgs.mkShell {
  buildInputs = [ sde pythonEnv ] ++ inputs.pkgs ++ kernelModules
                ++ (pkgs.lib.optional (baseboard == "aps_bf2556")
                  sde.pkgs.bf-platforms.aps_bf2556.salRefApp);

  shellHook =
    pkgs.lib.optionalString (baseboard == "aps_bf2556") ''
      export LD_LIBRARY_PATH=${pkgs.lib.strings.makeLibraryPath [ sde ]}
      export SAL_HOME=''${SAL_HOME:-${sde.pkgs.bf-platforms.aps_bf2556.salRefApp}}
    '' + pkgs.lib.optionalString bspLess ''
      export TOFINO_PORT_MAP=${bf-sde.platforms.${platform}.portMap}
    '' + ''
    export P4_INSTALL=~/.bf-sde/${sde.version}
    export SDE=${sde}
    export SDE_INSTALL=${sde}
    export SDE_BUILD=$P4_INSTALL/build
    export SDE_LOGS=$P4_INSTALL/logs
    export PTF_PYTHONPATH=${python.pkgs.makePythonPath inputs.ptfModules}
    export PTF_PATH=${pkgs.lib.strings.makeBinPath inputs.ptfPkgs}
    mkdir -p $P4_INSTALL $SDE_BUILD $SDE_LOGS

    cat <<EOF

    Intel Tofino SDE ${sde.version} on platform "${platform}"
  '' + pkgs.lib.optionalString bspLess ''

     Running in BSP-less mode with board port mapping $TOFINO_PORT_MAP

  '' + ''
    ${greetings.${platform} or greetings.asic}
    Build artifacts and logs are stored in $P4_INSTALL

    Use "exit" or CTRL-D to exit this shell.
    EOF
    PS1="\n\[\033[1;32m\][nix-shell(\[\033[31m\]SDE-${sde.version}\[\033[1;32m\]):\w]\$\[\033[0m\] "
  '' + pkgs.lib.optionalString (baseboard == "newport") ''
    echo
    echo "(Re-)Loading bf_fpga kernel module for ${platform}"
    sudo rmmod bf_fpga 2>/dev/null || true
    sudo $(type -p bf_fpga_mod_load)
  '' + pkgs.lib.optionalString (runCommand != "") ''
    echo "Executing command \"${runCommand}\""
    ${runCommand}
  '';
}
