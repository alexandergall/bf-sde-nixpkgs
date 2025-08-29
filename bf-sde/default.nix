{ withAsic, nixpkgs, p4lang-nixpkgs, pkgs }:

with pkgs;

let
  mkSDE = sdeSpec:
    let
      sdeSrc = sdeSpec.sde.src;

      extractSource = component:
        runCommand "sde-${self.version}-${component}.tgz" {}
          ''
            tar -czf $out -C ${sdeSrc}/pkgsrc/ ${component}
          '';

      ## Create a source tarball from a subdirectory in pkgsrc of the
      ## original SDE. The goal is to split the SDE into "components"
      ## that can be built as separate derivations to modularize the
      ## entire build.
      mkSrc = component: {
        pname = component;
        src = extractSource component;
        patches = sdeSpec.sde.patches.${component} or [];
      };

      ## Note that sdeSpec is merged with the sdePkgs scope. In
      ## particular, this can be used to implement global
      ## overrides. For example, "stdenv = gcc10Stdenv" in sdeSpec
      ## would have the effect of building all SDE packages with GCC
      ## 10.
      sdePkgs = lib.makeScope newScope (self: sdeSpec // {
        ## Tofino-only variant of p4c
        p4c = (import p4lang-nixpkgs {}).p4c.override {
          enableBMV2 = false;
          enableBPF = false;
          enableDPDK = false;
          enableP4TC = false;
          enableP4CGraphs = false;
        };
        buildSupport = self.callPackage ./build-support.nix {
          inherit sdeSpec;
        };
        isModel = platform:
          if builtins.match "^model.*" platform == null then
            false
          else
            true;
        target-syslibs = self.callPackage ./target-syslibs (mkSrc "target-syslibs");
        target-utils = self.callPackage ./target-utils (mkSrc "target-utils");
        bf-utils = self.callPackage ./bf-utils (mkSrc "bf-utils");
        bf-drivers = self.callPackage ./bf-drivers (mkSrc "bf-drivers"// {
          python = sdeSpec.python_bf_drivers;
        });
        bf-drivers-runtime = self.bf-drivers.override { runtime = true; };
        bf-diags = self.callPackage ./bf-diags (mkSrc "bf-diags");
        bf-platforms = import ./bf-platforms {
          inherit lib runCommand withAsic;
          inherit (sdeSpec) version bsps;
          inherit (self) callPackage buildSupport;
        };
        tofino-model = self.callPackage ./tofino-model (mkSrc "tofino-model");
        ptf-modules = self.callPackage ./ptf-modules (mkSrc "ptf-modules");
        ptf-utils = self.callPackage ./ptf-modules/utils.nix (mkSrc "ptf-modules");
        ptf-utils-runtime = self.ptf-utils.override { runtime = true; };
        bf-pktpy = self.callPackage ./ptf-modules/bf-pktpy.nix (mkSrc "ptf-modules");

        ## Standard kernel modules produced by the bf-drivers package,
        ## i.e. bf_kdrv, bf_knet, bf_kpkt. Also includes all
        ## baseboard-independent additional modules (or arbitrary
        ## other files) specified by the additionalModules attribute
        ## in kernels/default.nix.
        kernel-modules = import ./kernels {
          bf-drivers-src = extractSource "bf-drivers";
          inherit (self) version callPackage;
          inherit pkgs withAsic;

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
            newport = [ sdePkgs.bf-platforms.newport ];
            netberg_710 = [
              ## This doesn't contain any modules but a script that needs to
              ## have access to modules.
              (self.callPackage (import bf-platforms/netberg/i2c-utils.nix) {})
              (self.callPackage (import bf-platforms/netberg/optoe.nix) {})
            ];
            asterfusion = [
              self.bf-platforms.asterfusion.cgos
              self.bf-platforms.asterfusion.nct6779d
            ];
          };
        };
        ## Combination of kernel-modules with baseboard-specific
        ## modules and files.
        kernel-modules-baseboards =
          let
            baseboards = builtins.attrNames sdePkgs.bf-platforms;
            modulesForBaseboards = _: modules:
              let
                notBlacklisted = baseboard:
                  ! builtins.elem baseboard modules.baseboardBlacklist;
                baseboards' = builtins.filter notBlacklisted baseboards;
              in builtins.listToAttrs
                (map (baseboard:
                  {
                    name = baseboard;
                    value = modules.override { inherit baseboard; };
                  })
                  baseboards');
          in builtins.mapAttrs modulesForBaseboards sdePkgs.kernel-modules;
      });

      passthru = {
        inherit (sdeSpec) version;
        pkgs = {
          ## The set of SDE packages that we want to expose
          inherit (sdePkgs)
            p4c
            target-syslibs
            target-utils
            bf-utils
            bf-drivers
            bf-drivers-runtime
            bf-diags
            bf-platforms
            tofino-model
            ptf-modules
            ptf-utils
            ptf-utils-runtime
            bf-pktpy
            kernel-modules
            kernel-modules-baseboards;
        };
        test =
          let
            modelPlatforms = with builtins;
              lib.filterAttrs (n: v: match "model.*" n != null)
                (import ./bf-platforms/properties.nix);
            testForTarget = platform: target:
              lib.nameValuePair
                target
                rec {
                  programs = import ./p4-16-examples (mkSrc "p4-examples" // {
                    bf-sde = self;
                    inherit pkgs platform;
                  });
                  cases =
                    let
                      args = (import p4-16-examples/compose.nix {
                        bf-sde = self;
                        inherit pkgs platform;
                      }).args;
                      runTest = program:
                        let
                          testArgs = lib.attrsets.zipAttrsWith
                            (n: v: lib.flatten v) [ (args.${program.p4Name} or {})
                                                    (args.default or {}) ];
                        in program.runTest testArgs;
                    in lib.mapAttrs (_: program: runTest program) programs;
                  failed-cases = lib.filterAttrs (n: v: (import (v + "/passed") == false)) cases;
                };
          in
            lib.mapAttrs' (n: v: testForTarget n v.target) modelPlatforms;

        kernelIDFromRelease = kernelRelease:
          let
            kernel-modules = sdePkgs.kernel-modules;
            envKernelID = builtins.getEnv "SDE_KERNEL_ID";
            matches = lib.filterAttrs (_: spec: spec.kernelRelease == kernelRelease) kernel-modules;
            ids = lib.attrNames matches;
            nMatches = builtins.length ids;
          in
            if envKernelID != "" then
              builtins.trace ("Using kernel \"${envKernelID}\" from the environment, "
                              + "ignoring kernelRelease \"${kernelRelease}\"")
                (assert lib.assertMsg (builtins.hasAttr envKernelID kernel-modules)
                  "Unknown kernel ID \"${envKernelID}\"";
                  envKernelID)
            else
              if nMatches == 0 then
                builtins.trace "Unsupported kernel ${kernelRelease}, bf_switchd on TNA not available"
                  "none"
              else
                if nMatches == 1 then
                  builtins.head ids
                else
                  throw ("Multiple matches exist for kernel ${kernelRelease}. " +
                         "Chose one by setting SDE_KERNEL_ID to one of: ${lib.concatStringsSep ", " ids}");

        modulesForKernel = kernelRelease:
          builtins.getAttr (self.kernelIDFromRelease kernelRelease)
            sdePkgs.kernel-modules;

        ## A function that compiles a given P4 program in the context of
        ## the SDE.
        buildP4Program = sdePkgs.callPackage ./build-p4 {
          bf-sde = self;
        };

        baseboardForPlatform = platform:
          assert lib.assertOneOf "platform" platform (builtins.attrNames self.allPlatforms);
          assert lib.assertMsg ((! withAsic) -> sdePkgs.isModel platform)
            "Requested platform \"${platform}\" not available in non-ASIC mode. Only the model platforms are supported.";
          with builtins;
          let
            properties = self.allPlatforms.${platform};
            baseboard = properties.baseboard;
          in
            if (baseboard == null || hasAttr baseboard sdePkgs.bf-platforms) then
              assert lib.assertMsg (baseboard == null -> properties ? portMap)
                "Port-mapping file missing for BSP-less platform ${platform}";
              baseboard
            else
              if (properties ? portMap) then
                trace "No native platform support for ${platform}, falling back to BSP-less mode"
                  null
              else
                throw ("Platform ${platform} not supported in SDE ${self.version} "
                       + "and no BSP-less fallback provided");

        ## The set of all known platforms
        allPlatforms = import bf-platforms/properties.nix;

        ## The set of platforms supported by this SDE
        platforms = lib.filterAttrs (platform: _:
          (builtins.tryEval (self.baseboardForPlatform platform)).success)
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
          inherit (sdePkgs) isModel;
        };

        envCommand = sdePkgs.callPackage sde/env { inherit withAsic; };
        envStandalone = callPackage sde/env/standalone.nix {
          bf-sde = self;
          inherit nixpkgs p4lang-nixpkgs;
        };

        ## Support functions to create installers and a generic
        ## release manager for SDE-based P4 applications.
        support = import ./support self nixpkgs pkgs;
      };

      ## This is the full SDE, equivalent to what p4studio
      ## produces. It contains the reference BSP configured for the
      ## Tofino software model. The runtimeEnv* functions in passthru
      ## create runtime versions of this for particular BSPs.
      self = sdePkgs.callPackage ./sde {
        inherit passthru;
        src = sdeSrc;
        patches = sdeSpec.sde.patches or [];
        runtime = false;
        baseboard = "model";
      };
    in self;

  ## The BSP inputs are expected to be present in the store as fixed
  ## output derivations (added manually with "nix-store --add-fixed
  ## sha256 <...>"). The "outputHash" values below are the sha256 sums
  ## over those files.
  fetchFromStore = { name, outputHash, patches ? {}, ... }@args:
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
    } // args;

  bf-sde = with lib; mapAttrs (_: sdeSpec: mkSDE sdeSpec) rec {
    v9_13_4 = rec {
      version = "9.13.4";
      sde = {
        src = import ./src-for-asic {
          src = pkgs.fetchFromGitHub {
            repo = "open-p4studio";
            owner = "p4lang";
            rev = "4fc6e4";
            hash = "sha256-ohHb56B88exX0BmlyM7nz8ROUkP94vbeoUeskGZziT0=";
          };
          rdc = fetchFromStore {
            name = "bf-sde-9.13.4.tgz";
            outputHash = "1515fae8ec3abe644099c6cf3b9843bc1daaba1a6c39b3f57eb7b4edb5959669";
          };
          inherit withAsic runCommand;
        };
        patches = {
          mainCMake = [
            ## Set PYTHON_EXECUTABLE and PYTHON_COMMAND to the
            ## interpreter discovered via buildInputs, remove the
            ## third-party dependency discovery, that's taken care of
            ## by Nix.
            sde/PythonDependencies.cmake.patch

            ## Remove explicit invocations of scripts with the Python
            ## interpreter. The scripts are already properly wrapped
            ## to use the proper interpreter and environment.
            sde/P4Build.cmake.patch
          ];
          mainTools = [
            ## The native version of p4studio stores compiler
            ## artifacts in SDE_INSTALL. With our build, this is an
            ## immutable path in the Nix store. This patch uses a new
            ## environment variable P4_INSTALL to decouple the
            ## artifacts from the the installed SDE.
            sde/run_switchd.patch

            ## Remove explicit invocations of Python scripts, same
            ## rationale as above.
            sde/run_bfshell.patch
            sde/run_p4_tests.patch
          ];
          ptf-modules = [
            ## Run ptf command directly, same rationale as above.
            ptf-modules/run_ptf_tests.patch
          ];
        };
      };
      bsps = lib.optionalAttrs withAsic 
        {
          reference = fetchFromStore {
            name = "bf-reference-bsp-9.13.4.tgz";
            outputHash = "5bef42bcb885aaa59b237552e1f44789a74ebfc270b4d5685ba0dcf3f52e4381";
            patches = {
              newport = [
                bf-platforms/newport-eth-compliance.patch
                bf-platforms/newport-kernel-9.13.2.patch
                bf-platforms/newport-fix-per-media-lane-flags.patch
              ];
            };
          };
          netberg = fetchFromStore {
            name = "bf-platforms-netberg-7xx-bsp-9.13.2-240517.tgz";
            outputHash = "9b09f926d4233db75017f28678265deb16a3aa72483317a40180977053d5a987";
          };
          asterfusion = {
            src = fetchFromGitHub {
              owner = "asterfusion";
              repo = "bf-bsp-lts";
              rev = "f7a132e";
              sha256 = "0w0957d1kyhsyypl0z3gyaiz3r261vfwgnp2mnpxdagf1iwvfsgp";
            };
            ## Run gitver.sh in the cloned BSP to get this version ID
            asterfusion_version = "Git: r58 25.08";
            patches = {
              asterfusion = [ bf-platforms/asterfusion/bsp.patch ];
            };
            nct6779d = {
              src = fetchFromGitHub {
                owner = "asterfusion";
                repo = "nct6779d";
                rev = "732b62e";
                sha256 = "09x42rqsj9ra697jflrgkqj664pspq63akbrx6dw6kspcvswkf3a";
              };
              patches = [];
            };
            ## X-T Programmable Bare Metal User Manual v3.10.5-11, section 10.26,1
            ## https://drive.cloudswitch.io/external/745689ea25643bc00fac9224d368d4374ca3d15724cb83181a631c4168044d30
            cgoslx = fetchFromStore {
              name = "cgoslx-build-24.tar.gz";
              outputHash = "3738a81a5dd6ec06497ce132cb7dad606264752aa60762d02b338bc124f71504";
              patches = [
                bf-platforms/asterfusion/cgoslx.patch
              ];
            };
          };
        };
      ## Mimic what's supplied to the native p4studio on the supported
      ## build platforms.
      #stdenv = gcc10Stdenv;
      python_bf_drivers = python39;
    };
  };

in bf-sde // { latest = bf-sde.v9_13_4; }
