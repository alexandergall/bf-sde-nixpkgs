{ pkgs }:

with pkgs;

let
  kernels = import kernels/. pkgs;
  localRelease = import (runCommand "local-kernel-release" {}
    ''
      echo \"$(uname -r)\" >$out
    '');
  kernelID = builtins.getEnv "SDE_KERNEL_ID";
  selectLocalKernelID =
    if kernelID == ""
      then
        let
          matches = lib.filterAttrs (id: spec: spec.release == localRelease) kernels;
          ids = lib.attrNames matches;
          nMatches = builtins.length ids;
        in if nMatches == 0 then
            builtins.trace "Kernel ${localRelease} is unsupported, creating dummy package" ""
          else
            if nMatches == 1
              then
                lib.last ids
              else
                throw ''
                  Multiple matches for kernel ${localRelease}.
                  Chose one by setting SDE_KERNEL_ID to one of: ${lib.concatStringsSep ", " ids}
                ''
    else
      kernelID;

  ## If we are trying to build modules for the local kernel and
  ## that kernel is not in the list of supported kernels,
  ## we create this derivation instead which contains module load/unload
  ## commands terminating with an error.  This helps making P4
  ## programs create with buildP4Program fail in a clean manner.
  errorModules = stdenv.mkDerivation {
    name = "bf-sde-error-modules";
    unpackPhase = "true";
    installPhase = ''
        mkdir -p $out/bin
        for mod in kpkt kdrv knet; do
          load_cmd=$out/bin/bf_''${mod}_mod_load
          cat <<EOF >$load_cmd
        #!${runtimeShell}
        echo "No modules available for this kernel ($(uname -r))"
        exit 1
        EOF
        chmod a+x $load_cmd
        cp $load_cmd $out/bin/bf_''${mod}_mod_unload
        done
    '';
  };

  fixedDerivation = { name, outputHash }:
    builtins.derivation {
      inherit name outputHash;
      inherit system;
      builder = "none";
      outputHashMode = "flat";
      outputHashAlgo = "sha256";
    };

  mkSDE = sdeSpec:
    let
      sde = fixedDerivation sdeSpec.sde;
      bsp = fixedDerivation sdeSpec.bsp;

      extractSource = component:
        ## Assumes that all archives are .tgz and there is only
        ## one match with the extract wildcard match. Should
        ## probably check for errors.
        runCommand "bf-sde-${self.version}-${component}.tgz" {}
        ''
          mkdir tmp
          cd tmp
          tar -xf ${sde} --wildcards '*/packages/${component}*' --strip-components 2
          mv * $out
        '';

      mkSrc = component: {
        pname = component;
        src = extractSource component;
        patches = sdeSpec.patches.${component} or [];
      };

      callPackage = lib.callPackageWith (pkgs // sdePkgs // sdeSpec);
      sdePkgs = {
        bf-syslibs = callPackage ./bf-syslibs (mkSrc "bf-syslibs");
        bf-utils = callPackage ./bf-utils (mkSrc "bf-utils" // {
          bf-drivers-src = extractSource "bf-drivers";
        });
        bf-drivers = callPackage ./bf-drivers (mkSrc "bf-drivers");
        ## bf-diags is currently not used
        bf-diags = callPackage ./bf-diags (mkSrc "bf-diags");
        bf-platforms = callPackage ./bf-platforms {
          pname = "bf-platforms";
          src = bsp;
        };
        p4c = callPackage ./p4c (mkSrc "p4-compilers");
        tofino-model = callPackage ./tofino-model (mkSrc "tofino-model");
        p4-hlir = callPackage ./p4-hlir (mkSrc "p4-hlir");
        ptf-modules = callPackage ./ptf-modules (mkSrc "ptf-modules");
        ptf-utils = callPackage ./ptf-modules/utils.nix (mkSrc "ptf-modules");
        tools = callPackage ./tools {
          src = sde;
        };
        ## A stripped-down version of the SDE environment which only
        ## contains the components needed at runtime
        runtimeEnv = callPackage ./sde-runtime.nix {};
      };

      passthru = {
        inherit (sdeSpec) version;
        pkgs = sdePkgs;

        ## A function that compiles a given P4 program in the context of
        ## the SDE.
        buildP4Program = callPackage ./build-p4-program.nix {
          inherit callPackage;
          bf-sde = self;
        };

        ## A function that creates a command to run bf_switchd
        ## without a P4 program.
        buildP4DummyProgram =
          let
            p4Name = "bf-switchd-no_p4";
          in self.buildP4Program {
            pname = "bf-switchd-dummy";
            version = "1.0";
            src = null;
            requiredKernelModule = "bf_kpkt";
            inherit p4Name;
            overrides = {
              unpackPhase = "true";
              buildPhase = ''
                mkdir $out
                exec_name=${p4Name}
              '';
              postInstall = ''
                nlines=$(cat $command | wc -l)
                head -$((nlines - 1)) $command >$command.new
                cat <<EOF >> $command.new
                exec ${self}/bin/run_switchd.sh --skip-p4 -c ${self}/share/p4/targets/tofino/skip_p4.conf
                EOF
                mv $command.new $command
                chmod a+x $command
              '';
            };
          };

        ## A function which compiles the kernel modules for
        ## a particular kernel, identified by the attribute
        ## name of the set returned by kernels/default.nix
        buildModules = kernelID:
          let
            defaults = {
              patches = [];
              buildModulesOverrides = {};
            };
            spec = defaults // kernels.${kernelID};
          in if kernelID != "" then
            callPackage ./kernels/build-modules.nix ({
              inherit spec;
              src = extractSource "bf-drivers";
            } // spec.buildModulesOverrides)
          else
            errorModules;

        buildModulesForLocalKernel =
          self.buildModules selectLocalKernelID;

        ## A function that can be used with nix-shell to create an
        ## environment for developing data-plane and control-plane
        ## programs in the context of the SDE (see ./sde-env.sh).  The
        ## function takes an optional argument which must be a function
        ## that is called with the package set and returns a list of
        ## of packages to be included in the environment.
        ## packages to be included in the environment.
        mkShell = { inputFn ? pkgs: [] }:
          let
            inputs = (builtins.tryEval inputFn).value pkgs;
          in mkShell {
            ## kmod provides insmod, procps provides sysctl
            ## bf-drivers pulls in a Python2 environment with
            ## grpcio through its propagated build input.
            buildInputs = [ self self.pkgs.bf-drivers self.buildModulesForLocalKernel
                            kmod procps utillinux which ] ++ inputs;
            shellHook = ''
              export P4_INSTALL=~/.bf-sde/${self.version}
              export SDE=${self}
              export SDE_INSTALL=${self}
              export SDE_BUILD=$P4_INSTALL/build
              export SDE_LOGS=$P4_INSTALL/logs
              ## See comment in ./build_p4_program.nix regarding /usr/bin
              export PATH=$PATH:/usr/bin
              export PYTHONPATH=${self.pkgs.bf-drivers}/lib/python2.7/site-packages/tofino:$PYTHONPATH
              mkdir -p $P4_INSTALL $SDE_BUILD $SDE_LOGS

              cat <<EOF

              Barefoot SDE ${self.version}

              Load/unload kernel modules: $ sudo \$(type -p bf_{kdrv,kpkt,knet}_mod_{load,unload})

              Compile: $ p4_build.sh <p4name>.p4
              Run:     $ run_switchd -p <p4name>
              Run Tofino model:
                       $ sudo \$(type -p veth_setup.sh)
                       $ run_tofino_model -p <p4name>
                       $ run_switchd -p <p4name> -- --model
                       $ sudo \$(type -p veth_teardown.sh)

              Build artefacts and logs are stored in $P4_INSTALL

              Use "exit" or CTRL-D to exit this shell.

              EOF
              PS1="\n\[\033[1;32m\][nix-shell(\033[31mSDE-${self.version}\033[1;32m):\w]\$\[\033[0m\] "
            '';
          };

        testCases = import ./test-cases {
          inherit pkgs;
          bf-sde = self;
          srcSpec = mkSrc "p4-examples";
        };
        failedTests = lib.filterAttrs (n: v: (import (v + "/passed") == false))
                                      passthru.testCases;

        ## A derivation containing a script that starts a nix-shell in
        ## which P4 programs can be compiled and run in the context of
        ## the SDE
        support = runCommand "bf-sde-${self.version}-support" {} ''
          mkdir -p $out/bin
          substitute ${./sde-env.sh} $out/bin/sde-env-${self.version} \
            --subst-var-by VERSION ${builtins.replaceStrings [ "." ] [ "_" ] self.version}
          chmod a+x $out/bin/sde-env-${self.version}
        '';
      };
      self = callPackage ./sde.nix {
        inherit passthru;
      };
    in self;

  ## Download the SDE and BSP packages from the Intel repository
  ## and add them manually to the Nix store
  ##   nix-store --add-fixed sha256 <...>
  ## The hashes below are the "sha256sum" of these files.
  common = {
    curl = curl_7_52;
    patches = {
      p4-examples = [ ./test-cases/ptf.patch ];
    };
  };
  bf-sde = lib.mapAttrs (_: sdeSpec: mkSDE (lib.recursiveUpdate common sdeSpec)) {
    v9_1_1 = rec {
      version = "9.1.1";
      sde = {
        name = "bf-sde-${version}.tar";
        outputHash = "be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11";
      };
      bsp = {
        name = "bf-reference-bsp-${version}.tar";
        outputHash = "aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8";
      };
      stdenv = gcc7Stdenv;
      thrift = thrift_0_12;
    };
    v9_2_0 = rec {
      version = "9.2.0";
      sde = {
        name = "bf-sde-${version}.tar";
        outputHash = "94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26";
      };
      bsp = {
        name = "bf-reference-bsp-${version}.tar";
        outputHash = "d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac";
      };
      stdenv = gcc7Stdenv;
      thrift = thrift_0_12;
    };
    v9_3_0 = rec {
      version = "9.3.0";
      sde = {
        name = "bf-sde-${version}.tgz";
        outputHash = "566994d074ba93908307890761f8d14b4e22fb8759085da3d71c7a2f820fe2ec";
      };
      bsp = {
        name = "bf-reference-bsp-${version}.tgz";
        outputHash = "dd5e51aebd836bd63d0d7c37400e995fb6b1e3650ef08014a164124ba44e6a06";
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
      patches = {
        bf-drivers = [ ./bf-drivers/9.3.0-bfrtTable.py.patch ];
      };
    };
  };

in bf-sde // { latest = bf-sde.v9_3_0; }
