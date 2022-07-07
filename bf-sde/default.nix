{ pkgs, nixpkgsSrc }:

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
        buildSystem = callPackage ./build-system.nix {
          inherit sdeSpec;
        };
        isModel = platform:
          if builtins.match "^model.*" platform == null then
            false
          else
            true;
      });
      sdePkgs = {
        bf-syslibs = SDE.callPackage ./bf-syslibs (mkSrc "bf-syslibs");
        bf-utils = SDE.callPackage ./bf-utils (mkSrc "bf-utils" // {
          bf-drivers-src = extractSource "bf-drivers";
        });
        ## Dummy to satisfy callPackage for versions prior to 9.9.0
        bf-utils-tofino = {};
        bf-drivers = SDE.callPackage ./bf-drivers (mkSrc "bf-drivers"// {
          python = sdeSpec.python_bf_drivers;
        });
        bf-drivers-runtime = sdePkgs.bf-drivers.override { runtime = true; };
        ## bf-diags is currently not used
        bf-diags = SDE.callPackage ./bf-diags (mkSrc "bf-diags");
        bf-platforms = import ./bf-platforms {
          inherit lib runCommand;
          inherit (sdeSpec) version bsps;
          inherit (SDE) callPackage buildSystem;
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

          ## Originally, the kernel-modules packages contained only
          ## the modules from the bf-drivers component. Starting with
          ## the reference BSP for the Newport (Tofino2) baseboard,
          ## other components generate kernel modules as well. The
          ## idea is to collect them all in a single (per-kernel
          ## version) package. We currently use the following
          ## approach.
          ##
          ## The derivation that contains the new module is designed
          ## to take an argument "kernelSpec" with the default null.
          ## In that case, the derivation creates the package
          ## *without* the module. The derivation can then be
          ## overridden with kernelSpec holding the specification of
          ## the kernel for which to build the module. In that case,
          ## the derivation's output only contains the module and
          ## nothing else.
          ##
          ## The following set contains all of those derivations. It
          ## is passed to kernels/build-modules.nix which first builds
          ## the regular derivation for the modules from bf-drivers
          ## and then creates an environment that merges it with all
          ## of these additional derivations after their kernelSpec
          ## argument was overridden.
          ##
          ## The result is an environment that contains all kernel
          ## modules for the SDE.
          ##
          ## The list specified by the "default" attribute is applied
          ## unconditionally.  All other attributes are interpreted as
          ## the names of baseboards. This is used by
          ## build-p4/modules-wrapper.nix to include modules specific
          ## to a platform's baseboard.
          drvsWithKernelModules = {
            default = [];
            newport = lib.optionals (lib.versionAtLeast sdeSpec.version "9.7.0") [
              sdePkgs.bf-platforms.newport
            ];
            inventec = lib.optionals (lib.versionAtLeast sdeSpec.version "9.7.0") [
              (SDE.callPackage (import bf-platforms/inventec/onl-modules.nix) {})
            ];
          };
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
      }) // (lib.optionalAttrs (lib.strings.versionAtLeast sdeSpec.version "9.9.0") {

        ## bf-syslibs was renamed to target-syslibs. We keep bf-syslibs
        ## as the name of the package for simplicity.
        bf-syslibs = SDE.callPackage ./bf-syslibs (mkSrc "target-syslibs");

        ## bf-utils was split up into two separate components. The new
        ## bf-utils only contains Tofino-specific
        ## libraries. Everything else is now called target-utils. For
        ## the same reason as for bf-syslibs, we keep the name
        ## bf-utils for target-utils and use a new package
        ## bf-utils-tofino for the rest.
        bf-utils = SDE.callPackage ./bf-utils (mkSrc "target-utils" // {
          bf-drivers-src = extractSource "bf-drivers";
        });
        bf-utils-tofino = SDE.callPackage ./bf-utils/tofino.nix (mkSrc "bf-utils");
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
          assert lib.assertOneOf "platform" platform (builtins.attrNames self.allPlatforms);
          self.allPlatforms.${platform}.baseboard;

        ## The set of all known platforms
        allPlatforms = import bf-platforms/properties.nix;
        ## The set of platforms supported by this SDE
        platforms = lib.filterAttrs (_: prop:
          ## BSP-less platforms are supported in all SDEs
          prop.baseboard == null || builtins.hasAttr prop.baseboard sdePkgs.bf-platforms)
          self.allPlatforms;

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
          inherit (SDE) isModel;
        };

        envCommand = SDE.callPackage sde/env {};
        envStandalone = callPackage sde/env/standalone.nix {
          bf-sde = self;
          inherit nixpkgsSrc;
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
        p4-examples = [ ./p4-16-examples/ptf.patch ];
      };
    };
  };
  bf-sde = with pkgs; with lib; mapAttrs (_: sdeSpec: mkSDE (recursiveUpdate common sdeSpec)) rec {
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
          bf-drivers = [ ./bf-drivers/9.3.0-bfrtTable.py.patch ];
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
          name = "9.5.0_AOT1.5.4_SAL1.3.4.zip";
          outputHash = "510e5e18a91203fe6c4c0aabd807eb69ad53224500f7cb755f7c5b09c8e4525d";
          patches = {
            aps_bf2556 = [ bf-platforms/aps/bf_pltfm_smb.patch ];
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
    };
    v9_6_0 = rec {
      version = "9.6.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "0e73fd8e7fe22c62cafe7dc4415649f0e66c04607c0056bd08adc1c7710fd193";
        patches = {
          mainTools = [ sde/run_switchd.patch sde/run_bfshell-9.6.0.patch
                        sde/run_p4_tests-9.6.0.patch ];
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
          ## This patch is a simple workaround for a bug that affects
          ## the Tofino2 driver. The bug causes several (harmless)
          ## error messages about out-of-bound values getting logged
          ## whenever the $PORT pseudo-table is queried via BFRT. The
          ## workaround simply sets these values to zero to make the
          ## bounds check succeed (the affected values are for the
          ## $SDS_TX_{PRE,POST} fields in the table, I don't know what
          ## these are but they seem to be irrelevant for typical
          ## use-cases). The issue is tracked as Intel JIRA issue
          ## DRV-6313.
          bf-drivers = [ bf-drivers/port-table-field-size-workaround.patch ];
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
          patches = {
            default = [ bf-platforms/reference-get-media-type.patch ];
            newport = [ bf-platforms/newport-eth-compliance.patch ];
          };
        };
        aps = fetchFromStore {
          name = "9.7.0_AOT1.6.1_SAL1.3.5_2.zip";
          outputHash = "4941987c4489d592de9b3676c79cb2011a22fe329425e8876fa8ae026fc959ad";
          patches = {
            aps_bf2556 = [ bf-platforms/aps/bf_pltfm_smb-9.7.0.patch ];
          };
        };
        inventec = fetchFromStore {
          name = "bf-platform_SRC_9.7.0.2.1.tgz";
          outputHash = "8391d5e791ae8b453711a79ed6f6d4372bd9ed6076b3ff54c649b69775b8d9c9";
        };
        netberg = fetchFromStore {
          name = "bf-platforms-netberg-7xx-bsp-9.7.0-220210.tgz";
          outputHash = "ad140a11fd39f7fbd835d6774d9b855f2ba693fd1d2e61b45a94aa30ed08a4f1";
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_13;
      libcli = libcli1_10;
      python_bf_drivers = python3;
    };
    v9_7_1 = lib.recursiveUpdate v9_7_0 rec {
      version = "9.7.1";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "dc0eb79b04797a7332f3995f37533a255a9a12afb158c53cdd421d1d4717ee28";
        inherit (v9_7_0.sde) patches;
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "78aa14c5ec463cd4025b241e898e812c980bcd5e4d039213e397fcb6abb61c66";
          inherit (v9_7_0.bsps.reference) patches;
        };
      };
    };
    v9_7_2 = lib.recursiveUpdate v9_7_0 rec {
      version = "9.7.2";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "e8cf3ef364e33e97f6af6dd4e39331221d61c951ffea30cc7221a624df09e4ed";
        inherit (v9_7_0.sde) patches;
      };
      bsps = {
        reference = fetchFromStore {
          name = "bf-reference-bsp-${version}.tgz";
          outputHash = "d578438c44a19d2162079d9e4a4a5363a1503a64d7b05e96ceca96dc216f2380";
          inherit (v9_7_0.bsps.reference) patches;
        };
      };
    };
    v9_8_0 = rec {
      version = "9.8.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "8d367f0812f17e64cef4acbe2c10130ae4b533bf239e554dc6246c93f826c12a";
        patches = {
          mainTools = [ sde/run_switchd-9.7.0.patch sde/run_bfshell-9.7.0.patch
                        sde/run_p4_tests-9.7.0.patch ];
          mainCMake = [ sde/P4Build.cmake.patch ];
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
          outputHash = "975fa33e37abffa81ff01c1142043907f05726e31efcce0475adec0f1a80f919";
          patches = {
            newport = [ bf-platforms/newport-eth-compliance.patch ];
          };
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_14;
      libcli = libcli1_10;
      python_bf_drivers = python3;
    };
    v9_9_0 = rec {
      version = "9.9.0";
      sde = fetchFromStore {
        name = "bf-sde-${version}.tgz";
        outputHash = "c4314e76140a9a6f5d644176e0e3b0ca88f0df606b735c2c47c7cf5575d46257";
        patches = {
          mainTools = [ sde/run_switchd-9.7.0.patch sde/run_bfshell-9.7.0.patch
                        sde/run_p4_tests-9.7.0.patch ];
          mainCMake = [ sde/P4Build.cmake.patch ];
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
          outputHash = "f73aecac5eef505a56573c6c9c1d32e0fa6ee00218bc08e936fff966f8d2f87a";
          patches = {
            newport = [ bf-platforms/newport-eth-compliance.patch ];
          };
        };
      };
      stdenv = gcc8Stdenv;
      thrift = thrift_0_14;
      libcli = libcli1_10;
      python_bf_drivers = python3;
    };
  };

in bf-sde // { latest = bf-sde.v9_9_0; }
