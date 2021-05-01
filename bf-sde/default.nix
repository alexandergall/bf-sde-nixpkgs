{ pkgs }:

with pkgs;

let
  fixedDerivation = { name, outputHash }:
    builtins.derivation {
      inherit name outputHash system;
      builder = runCommand "SDE-archive-error" {} ''
        echo
        echo "Missing SDE component ${name}"
        echo "Please add it to the Nix store with"
        echo
        echo "  nix-store --add-fixed sha256 ${name}"
        echo
        exit 1
      '';
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
        bf-drivers = callPackage ./bf-drivers (mkSrc "bf-drivers"// {
          python = sdeSpec.python_bf_drivers;
        });
        bf-drivers-runtime = sdePkgs.bf-drivers.override { runtime = true; };
        ## bf-diags is currently not used
        bf-diags = callPackage ./bf-diags (mkSrc "bf-diags");
        bf-platforms = callPackage ./bf-platforms {
          pname = "bf-platforms";
          src = bsp;
        };
        p4c = callPackage ./p4c (mkSrc "p4-compilers");
        tofino-model = callPackage ./tofino-model (mkSrc "tofino-model");
        ptf-modules = callPackage ./ptf-modules (mkSrc "ptf-modules");
        ptf-utils = callPackage ./ptf-modules/utils.nix (mkSrc "ptf-modules");
        kernel-modules = import ./kernels {
          bf-drivers-src = extractSource "bf-drivers";
          inherit pkgs callPackage;
        };
        ## A stripped-down version of the SDE environment which only
        ## contains the components needed at runtime
        runtimeEnv = callPackage ./sde {
          runtime = true;
          src = sde;
        };
      } // (lib.optionalAttrs (lib.strings.versionAtLeast sdeSpec.version "9.5.0") {

        ## Up to 9.4.0, the test facility used the PTF from p4.org
        ## (included with ptf-modules) with scapy to generate packets.
        ## Due to some licensing issue with scapy (according to the
        ## 9.5.0 release notes), the SDE uses a modified version of
        ## the PTF that no longer depends on scapy starting with
        ## 9.5.0.  Instead, it uses a packet generator called
        ## "bf-pktpy" provided by Intel.  The modified PTF executable
        ## is installed as "bf-ptf" (as expected by run_ptf_tests.py
        ## fomr ptf-utils).  p4studio_build also moves the modules of
        ## the PTF to a subdirectory "bf-ptf" in site-packages to make
        ## it possible to install the original p4.org PTF on top of
        ## it.  We don't replicate this behaviour.
        ptf-modules = callPackage ./ptf-modules/bf-ptf.nix (mkSrc "ptf-modules");
        bf-pktpy = callPackage ./ptf-modules/bf-pktpy.nix (mkSrc "ptf-modules");
      });

      passthru = {
        inherit (sdeSpec) version;
        pkgs = sdePkgs;
        test = rec {
          programs = import ./p4-16-examples (mkSrc "p4-examples" // {
            bf-sde = self;
            inherit (pkgs) lib;
          });
          cases =
            let
              runTest = program:
                let
                  args = (import (./p4-16-examples + "/${self.version}.nix")).args.${program.p4Name} or {};
                in program.runTest args;
             in lib.mapAttrs (_: program: runTest program) programs;
          failed-cases = lib.filterAttrs (n: v: (import (v + "/passed") == false)) cases;
        };

        modulesForKernel = kernelRelease:
          (callPackage kernels/select-modules.nix {
             inherit (self.pkgs) kernel-modules;
           }) kernelRelease;

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
            examples = stdenv.mkDerivation {
              pname = "p4-examples";
              version = "${self.version}";
              inherit (mkSrc "p4-examples") src;
            };
            skipP4Conf = runCommand "tofino-skip_p4.conf" {} ''
              cp ${examples}/share/p4/targets/tofino/skip_p4.conf $out
            '';
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
                exec ${self.pkgs.runtimeEnv}/bin/run_switchd.sh --skip-p4 -c ${skipP4Conf}
                EOF
                mv $command.new $command
                chmod a+x $command
              '';
            };
          };

        ## A function that can be used with nix-shell to create an
        ## environment for developing data-plane and control-plane
        ## programs in the context of the SDE (see ./sde-env.sh).
        mkShell = { inputFn ? { pkgs, pythonPkgs }: {}, kernelRelease }:
          let
            bf-drivers = self.pkgs.bf-drivers;
            python = bf-drivers.pythonModule;
            defaultInputs = {
              pkgs = [];
              cpModules = [];
              ptfModules = [];
            };
            inputs = defaultInputs // (builtins.tryEval inputFn).value {
              inherit pkgs;
              pythonPkgs = python.pkgs;
            };
            pythonEnv = python.withPackages (ps: [ bf-drivers ]
                                                 ++ inputs.cpModules);
          in mkShell {
            ## kmod provides insmod, procps provides sysctl
            buildInputs = [ self (self.modulesForKernel kernelRelease) pythonEnv ]
                            ++ inputs.pkgs;
            shellHook = ''
              export P4_INSTALL=~/.bf-sde/${self.version}
              export SDE=${self}
              export SDE_INSTALL=${self}
              export SDE_BUILD=$P4_INSTALL/build
              export SDE_LOGS=$P4_INSTALL/logs
              export PTF_PYTHONPATH=${python.pkgs.makePythonPath inputs.ptfModules}
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
              Run PTF tests: run the Tofino model, then
                       $ run_p4_tests.sh -p <p4name> -t <path-to-dir-with-test-scripts>

              Build artefacts and logs are stored in $P4_INSTALL

              Use "exit" or CTRL-D to exit this shell.

              EOF
              PS1="\n\[\033[1;32m\][nix-shell(\033[31mSDE-${self.version}\033[1;32m):\w]\$\[\033[0m\] "
            '';
          };


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

      ## This is the full SDE, equivalent to what p4studio
      ## produces.
      self = callPackage ./sde {
        inherit passthru;
        src = sde;
        runtime = false;
      };
    in self;

  ## Download the SDE and BSP packages from the Intel repository
  ## and add them manually to the Nix store
  ##   nix-store --add-fixed sha256 <...>
  ## The hashes below are the "sha256sum" of these files.
  common = {
    curl = curl_7_52;
    ## The Python version to use when building bf-drivers. Every
    ## derivation using bf-drivers as input must use the same version
    ## by referencing bf-drivers.pythonModule
    python_bf_drivers = python2;
    patches = {
      p4-examples = [ ./p4-16-examples/ptf.patch ];
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
    v9_3_1 = rec {
      version = "9.3.1";
      sde = {
        name = "bf-sde-${version}.tgz";
        outputHash = "71db320fa7d12757127c7da1c16ea98453f4c88ecca7853c73b2bd4dccd1d891";
      };
      bsp = {
        name = "bf-reference-bsp-${version}.tgz";
        outputHash = "b934601c77b08c3281f8dcb235450b80316a42e2683ff29e4c9f2485fffbb51f";
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
    };
    v9_4_0 = rec {
      version = "9.4.0";
      sde = {
        name = "bf-sde-${version}.tgz";
        outputHash = "daec162c2a857ae0175e57ab670b59341d39f3ac2ecd5ba99ec36afa15566c4e";
      };
      bsp = {
        name = "bf-reference-bsp-${version}.tgz";
        outputHash = "269eecaf3186d7c9a061f6b66ce3d1c85d8f2022ce3be81ee9e532d136552fa4";
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
      patches = {
        p4-examples = [ ./p4-16-examples/9.4.0-ptf.patch ];
      };
    };
    v9_5_0 = rec {
      version = "9.5.0";
      sde = {
        name = "bf-sde-${version}.tgz";
        outputHash = "61d55a06fa6f80fc1f859a80ab8897eeca43f06831d793d7ec7f6f56e6529ed7";
      };
      bsp = {
        name = "bf-reference-bsp-${version}.tgz";
        outputHash = "b6a293c8e2694d7ea8d7b12c24b1d63c08b0eca3783eeb7d54e8ecffb4494c9f";
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
      patches = {
        p4-examples = [];
      };
    };
  };

in bf-sde // { latest = bf-sde.v9_5_0; }
