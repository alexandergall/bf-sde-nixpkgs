{ pkgs }:

with pkgs;

let
  mkSDE = sdeSpec:
    let
      sdeSrc = sdeSpec.sde.src;

      extractSource = component:
        ## Assumes that all archives are .tgz and there is only
        ## one match with the extract wildcard match. Should
        ## probably check for errors.
        runCommand "bf-sde-${self.version}-${component}.tgz" {}
        ''
          mkdir tmp
          cd tmp
          tar -xf ${sdeSrc} --wildcards '*/packages/${component}*' --strip-components 2
          mv * $out
        '';

      mkSrc = component: {
        pname = component;
        src = extractSource component;
        patches = sdeSpec.sde.patches.${component} or [];
      };

      SDE = lib.makeScope pkgs.newScope (self: sdePkgs // sdeSpec // {
        buildSystem = callPackage ./build-system {
          inherit sdeSpec;
        };
      });
      sdePkgs = {
        bf-syslibs = SDE.callPackage ./bf-syslibs (mkSrc "bf-syslibs");
        bf-utils = SDE.callPackage ./bf-utils (mkSrc "bf-utils" // {
          bf-drivers-src = extractSource "bf-drivers";
        });
        bf-drivers = SDE.callPackage ./bf-drivers (mkSrc "bf-drivers"// {
          python = sdeSpec.python_bf_drivers;
        });
        bf-drivers-runtime = sdePkgs.bf-drivers.override { runtime = true; };
        ## bf-diags is currently not used
        bf-diags = SDE.callPackage ./bf-diags (mkSrc "bf-diags");
        bf-platforms = import ./bf-platforms {
          inherit lib;
          inherit (sdeSpec) bsps;
          inherit (SDE) callPackage;
        };
        p4c = SDE.callPackage ./p4c (mkSrc "p4-compilers");
        tofino-model = SDE.callPackage ./tofino-model (mkSrc "tofino-model");
        ptf-modules = SDE.callPackage ./ptf-modules (mkSrc "ptf-modules");
        ptf-utils = SDE.callPackage ./ptf-modules/utils.nix (mkSrc "ptf-modules");
        ptf-utils-runtime = sdePkgs.ptf-utils.override { runtime = true; };
        kernel-modules = import ./kernels {
          bf-drivers-src = extractSource "bf-drivers";
          inherit (SDE) callPackage;
          inherit pkgs;
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
        ptf-modules = SDE.callPackage ./ptf-modules/bf-ptf.nix (mkSrc "ptf-modules");
        bf-pktpy = SDE.callPackage ./ptf-modules/bf-pktpy.nix (mkSrc "ptf-modules");
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
          (SDE.callPackage kernels/select-modules.nix {
             inherit (self.pkgs) kernel-modules;
           }) kernelRelease;

        ## A function that compiles a given P4 program in the context of
        ## the SDE.
        buildP4Program = SDE.callPackage ./build-p4 {
          bf-sde = self;
        };

        baseboardForPlatform = platform:
          let
            properties = import bf-platforms/properties.nix;
          in assert lib.assertMsg (builtins.hasAttr platform properties) "Unknown platform: ${platform}";
            properties.${platform}.baseboard;

        runtimeEnv = baseboard:
          self.override {
            inherit baseboard;
            runtime = true;
            passthru = {};
          };

        runtimeEnv' = platform:
          self.runtimeEnv (self.baseboardForPlatform platform);

        ## A version of the runtime environment that does not contain
        ## a BSP. This is useful when only components are needed that
        ## do not require a BSP, for example the run_bfshell.sh
        ## utility.
        runtimeEnvNoBsp = self.runtimeEnv null;

        ## A function that can be used with nix-shell to create an
        ## environment for developing data-plane and control-plane
        ## programs in the context of the SDE.
        mkShell = import sde/mk-shell.nix {
          bf-sde = self;
          inherit pkgs;
        };

        ## Support functions to create installers and a generic
        ## release manager for SDE-based P4 applications.
        support = import ./support pkgs;
      };

      ## This is the full SDE, equivalent to what p4studio
      ## produces. It contains the reference BSP configured for the
      ## Tofino software model. The runtimeEnv* functions in passthru
      ## create runtime versions of this for particular BSPs.
      self = SDE.callPackage ./sde {
        inherit passthru;
        src = sdeSrc;
        patches = sdeSpec.sde.patches or [];
        runtime = false;
        baseboard = "model";
      };
    in self;

  ## The SDE and BSP inputs are expected to be present in the store as
  ## fixed output derivations (added manually with "nix-store
  ## --add-fixed sha256 <...>"). The "outputHash" values below are the
  ## sha256 sums over those files.
  fetchFromStore = { name, outputHash, patches ? {} }:
    {
      src = builtins.derivation {
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
      inherit patches;
    };

  common = {
    curl = curl_7_52;
    ## The Python version to use when building bf-drivers. Every
    ## derivation using bf-drivers as input must use the same version
    ## by referencing bf-drivers.pythonModule
    python_bf_drivers = python2;
    sde = {
      patches = {
        mainTools = [ sde/run_switchd.patch sde/run_bfshell.patch sde/run_p4_tests.patch ];
        bf-drivers = [ bf-drivers/bf_switchd_model.patch ];
        p4-examples = [ ./p4-16-examples/ptf.patch ];
      };
    };
  };
  bf-sde = with pkgs; with lib; mapAttrs (_: sdeSpec: mkSDE (recursiveUpdate common sdeSpec)) {
    v9_1_1 = rec {
      version = "9.1.1";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tar";
        outputHash = "be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11";
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tar";
          outputHash = "aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8";
        };
      };
      stdenv = gcc7Stdenv;
      thrift = thrift_0_12;
    };
    v9_2_0 = rec {
      version = "9.2.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tar";
        outputHash = "94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26";
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tar";
          outputHash = "d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac";
        };
      };
      stdenv = gcc7Stdenv;
      thrift = thrift_0_12;
    };
    v9_3_0 = rec {
      version = "9.3.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "566994d074ba93908307890761f8d14b4e22fb8759085da3d71c7a2f820fe2ec";
        patches = {
          bf-drivers = [ ./bf-drivers/9.3.0-bfrtTable.py.patch
                         bf-drivers/bf_switchd_model.patch ];
        };
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "dd5e51aebd836bd63d0d7c37400e995fb6b1e3650ef08014a164124ba44e6a06";
        };
        inventec = fetchFromStore {
          name = "bf-inventec-bsp93.tgz";
          outputHash = "fd1e4852d0b7543dd5d2b81ab8e0150644a0f24ca87d59f1369216f1a6e796ad";
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
    };
    v9_3_1 = rec {
      version = "9.3.1";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "71db320fa7d12757127c7da1c16ea98453f4c88ecca7853c73b2bd4dccd1d891";
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "b934601c77b08c3281f8dcb235450b80316a42e2683ff29e4c9f2485fffbb51f";
        };
        inventec = fetchFromStore {
          name = "bf-inventec-bsp93.tgz";
          outputHash = "fd1e4852d0b7543dd5d2b81ab8e0150644a0f24ca87d59f1369216f1a6e796ad";
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
    };
    v9_4_0 = rec {
      version = "9.4.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "daec162c2a857ae0175e57ab670b59341d39f3ac2ecd5ba99ec36afa15566c4e";
        patches = {
          p4-examples = [ ./p4-16-examples/9.4.0-ptf.patch ];
        };
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "269eecaf3186d7c9a061f6b66ce3d1c85d8f2022ce3be81ee9e532d136552fa4";
        };
        aps = fetchFromStore {
          name = "9.5.0_AOT1.5.1_SAL1.3.2.zip";
          outputHash = "2e56f51233c0eef1289ee219582ea0ec6d7455c3f78cac900aeb2b8214df0544";
        };
        inventec = fetchFromStore {
          name = "bf-inventec-bsp93.tgz";
          outputHash = "fd1e4852d0b7543dd5d2b81ab8e0150644a0f24ca87d59f1369216f1a6e796ad";
          patches = {
            default = [ bf-platforms/bf-inventec-bsp93.patch ];
          };
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
    };
    v9_5_0 = rec {
      version = "9.5.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "61d55a06fa6f80fc1f859a80ab8897eeca43f06831d793d7ec7f6f56e6529ed7";
        patches = {
          mainTools = [ sde/run_switchd.patch sde/run_bfshell.patch
                        sde/run_p4_tests-9.5.0.patch ];
          p4-examples = [];
        };
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "b6a293c8e2694d7ea8d7b12c24b1d63c08b0eca3783eeb7d54e8ecffb4494c9f";
        };
        aps = fetchFromStore {
          name = "9.5.0_AOT1.5.1_SAL1.3.2.zip";
          outputHash = "2e56f51233c0eef1289ee219582ea0ec6d7455c3f78cac900aeb2b8214df0544";
        };
        inventec = fetchFromStore {
          name = "bf-inventec-bsp93.tgz";
          outputHash = "fd1e4852d0b7543dd5d2b81ab8e0150644a0f24ca87d59f1369216f1a6e796ad";
          patches = {
            default = [ bf-platforms/bf-inventec-bsp93.patch ];
          };
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
    };
    v9_6_0 = rec {
      version = "9.6.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "0e73fd8e7fe22c62cafe7dc4415649f0e66c04607c0056bd08adc1c7710fd193";
        patches = {
          mainTools = [ sde/run_switchd.patch sde/run_bfshell-9.6.0.patch
                        sde/run_p4_tests-9.6.0.patch ];
          bf-syslibs = [ bf-syslibs/bf-sal-CMakeLists.txt.patch ];
          bf-drivers = [ bf-drivers/libpython-dependency.patch
                         bf-drivers/bf_switchd_model.patch ];
          p4-examples = [];
        };
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "88cb4b0978f23c28499faff75098f939374d9071859593353a18c2235e0be461";
          patches = {
            default = [ bf-platforms/reference-get-media-type.patch ];
          };
        };
        inventec = fetchFromStore {
          name = "bf-inventec-bsp93.tgz";
          outputHash = "fd1e4852d0b7543dd5d2b81ab8e0150644a0f24ca87d59f1369216f1a6e796ad";
          patches = {
            default = [ bf-platforms/bf-inventec-bsp93.patch ];
          };
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
      libcli = libcli1_10;
    };
    v9_7_0 = rec {
      version = "9.7.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "a4ca94f2d9602535c52613f9d8ad3504b55d99283a4e3dfc64de19e24d767423";
        patches = {
          mainTools = [ sde/run_switchd-9.7.0.patch sde/run_bfshell-9.7.0.patch
                        sde/run_p4_tests-9.7.0.patch ];
          mainCMake = [ sde/P4Build.cmake.patch ];
          bf-drivers = [ bf-drivers/libpython-dependency-9.7.0.patch
                         bf-drivers/bf_switchd_model.patch ];
          p4-examples = [];
          ptf-modules = [ ptf-modules/run_ptf_tests.patch
                          ## The getmac module used by bf-pktpy
                          ## returns None as MAC address if run in a
                          ## VM. This patch sets a static address in
                          ## this case.
                          ptf-modules/getmac.patch ];
        };
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "87f91540c0947edff2694cea9beeca78f95062b0aaca812a81c238ff39343e46";
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
      libcli = libcli1_10;
      python_bf_drivers = python3;
    };
  };

in bf-sde // { latest = bf-sde.v9_7_0; }
