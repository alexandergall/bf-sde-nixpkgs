{ stdenv, callPackage, procps, kmod, lib, buildEnv, coreutils, gnused,
  gnugrep, bash, jq, bf-sde, isModel }:

{ pname,
  version,
# The name of the p4 program to compile without the ".p4" extension
  p4Name,
# The name to use for the generated script that starts bf_switchd
# with the program
  execName ? p4Name,
# The path to the program relative to the root of the source tree.
# I.e. the program to be compiled si expected to be
#   <path>/<p4Name>.p4
  path ? ".",
# The platform for which to build. This selects which
# baseboard-dependent platform manager library gets installed into the
# runtime environment.
  platform ? "model",
# The kernel module required by bf_switchd for this program, one
# of bf_kdrv, bf_kpkt, bf_knet. Used by the makeModuleWrapper
# support function to load the module before executing bf_switchd.
  requiredKernelModule ? null,
# Target to compile for, defaults to the platform's intrinsic
# target. The build_p4.sh script for SDEs older than 9.7.0 don't
# support building for any other target than tofino.
  target ?
  assert lib.assertOneOf "platform" platform (builtins.attrNames bf-sde.platforms);
  bf-sde.platforms.${platform}.target,
# The flags passed to the p4_build.sh script
  buildFlags ? [],
  src,
# Optional patches
  patches ? [],
# Create the artifacts package without dependencies. This has no
# effect for SDEs older than 9.7.0. For 9.7.0 and above, it causes
# files like source.json and frontend-ir.json to be omitted from
# the package (they cause dependencies on the P4 source code and
# the P4 compiler package)
  pureArtifacts ? true
}:

assert requiredKernelModule != null -> lib.assertOneOf "kernel module"
  requiredKernelModule [ "bf_kdrv" "bf_kpkt" "bf_knet" ];

assert target != null -> lib.assertOneOf "target" target [ "tofino" "tofino2" "tofino3" ];

assert lib.versionOlder bf-sde.version "9.7.0" ->
       lib.assertMsg (target == "tofino")
         "Target \"${target}\" not supported in SDEs prior to 9.7.0";

let
  targetFlag = {
    tofino = "-DTOFINO=ON";
    tofino2 = "-DTOFINO2=ON";
    tofino3 = "-DTOFINO3=ON";
  }.${target};

  runtimeEnv = bf-sde.runtimeEnv' platform;

  ## The SAL wrapper for the aps_bf2556 platform currently requires
  ## that the build artifacts are located in the runtime environment.
  runtimeEnvWithArtifacts = buildEnv {
    name = runtimeEnv.name + "-${p4Name}-artifacts";
    paths = [ runtimeEnv build ];
  };

  baseboard = bf-sde.baseboardForPlatform platform;
  bspLess = baseboard == null;
  passthru = {
    inherit p4Name platform target baseboard;

    ## Build a shell script to load the required kernel module for a given
    ## kernel before executing the program.
    moduleWrapper' = modules:
      callPackage ./modules-wrapper.nix {
        inherit execName self bf-sde;
        modules = modules.override { inherit baseboard; };
        requiredKernelModule =
          if isModel platform then
            null
          else
            requiredKernelModule;
      };

    moduleWrapper = kernelRelease:
      self.moduleWrapper' (bf-sde.modulesForKernel kernelRelease);

    runTest = args:
      let
        ## Re-create the patched source tree to exercise the PTF tests
        src' = stdenv.mkDerivation {
          name = "${pname}-${version}-source";
          inherit src patches;
          phases = [ "unpackPhase" "patchPhase" "installPhase" ];
          installPhase = ''
            mkdir $out
            tar cf - . | tar -C $out -xf -
          '';
        };
      in callPackage ./run-test.nix ({
        inherit self p4Name bf-sde build;
        src = src';
        ## Default directory of PTF test scripts relative to
        ## the source tree
        testDir = path;
      } // args);
  };

  ## Create a separate derivation for the P4 artifacts that does not
  ## depend on the runtime environment (i.e. on the platform).
  build = stdenv.mkDerivation {
    buildInputs = [ bf-sde jq ];
    pname = "${execName}-artifacts";
    inherit version src p4Name patches buildFlags;

    buildPhase =
      assert lib.assertMsg (bspLess -> target == "tofino")
        "${platform}/${target}: bsp-less mode only supported for tofino target";
      ''
        set -e
        export P4_INSTALL=$out
        export TOFINO_PORT_MAP=${bf-sde.platforms.${platform}.portMap or ""}
      '' + (if lib.versionOlder bf-sde.version "9.7.0" then ''
      export SDE_BUILD=$TEMP
      export SDE_LOGS=$TEMP
      mkdir $out
      path=${path}
      exec_name="${p4Name}"
      if [ "${p4Name}" != "${execName}" ]; then
        ln -s ${p4Name}.p4 $path/${execName}.p4
        exec_name=${execName}
      fi
      echo "Building \"${p4Name}.p4\" as \"${execName}\" with p4c flags \"$buildFlags\""
      ${bf-sde}/bin/p4_build.sh $buildFlags $path/$exec_name.p4
    '' else (
      ''
        echo "Building \"${p4Name}.p4\" as \"${execName}\" for target \"${target}\" with p4c flags \"$buildFlags\""
        ${bf-sde}/bin/p4_build.sh --p4-name=${execName} --p4c-flags="$buildFlags" \
          --cmake-flags ${targetFlag} $(realpath ${path}/${p4Name}.p4)
        rm -rf $out/build
      '' + lib.optionalString pureArtifacts ''
        find $out/share \( -name source.json -o -name frontend-ir.json \) -exec rm {} \;
      ''
    ));

    installPhase = ''true'';
  };

  self = stdenv.mkDerivation {
    inherit pname version passthru;
    phases = [ "installPhase" "fixupPhase" ];
    installPhase = ''
      mkdir -p $out/bin

      EXEC_NAME=${p4Name}
      ARCH=${target}
      [ "${p4Name}" != "${execName}" ] && EXEC_NAME=${execName}
      BUILD=${build}
      RUNTIME_ENV=${runtimeEnv}
    '' +
    ({
      model = ''
        substitute ${./run-model.sh} $out/bin/$EXEC_NAME \
          --subst-var BUILD \
          --subst-var RUNTIME_ENV \
          --subst-var EXEC_NAME \
          --subst-var ARCH \
          --subst-var-by bash ${bash}/bin/bash \
          --subst-var-by pkill ${procps}/bin/pkill \
          --subst-var-by rmmod ${kmod}/bin/rmmod \
          --subst-var-by sleep ${coreutils}/bin/sleep
        chmod a+x $out/bin/$EXEC_NAME
      '';
      aps_bf2556 = ''
        RUNTIME_ENV_WITH_ARTIFACTS=${runtimeEnvWithArtifacts}
        APS_SAL_REFAPP=${bf-sde.pkgs.bf-platforms.aps_bf2556.salRefApp}
        P4_PROG=$EXEC_NAME
        _PATH=${lib.strings.makeBinPath [ coreutils gnused gnugrep ]}
        _LD_LIBRARY_PATH=${lib.strings.makeLibraryPath [ runtimeEnvWithArtifacts ]}
        substitute ${./run-aps_bf2556.sh} $out/bin/$EXEC_NAME \
          --subst-var RUNTIME_ENV_WITH_ARTIFACTS \
          --subst-var APS_SAL_REFAPP \
          --subst-var P4_PROG \
          --subst-var _PATH \
          --subst-var _LD_LIBRARY_PATH
        chmod a+x $out/bin/$EXEC_NAME
      '';
    }.${if bspLess then "" else baseboard} or (
      lib.optionalString bspLess ''
        BANNER=\
        '=============================================================\n'\
        'NOTE: This platform is supported in \"BSP-less\" mode only.\n'\
        'There is no access to any platform-specific information, e.g.\n'\
        '   * Transceiver modules\n'\
        '   * LEDs\n'\
        '   * Sensors\n'\
        '   * Power supplies/Fan modules\n'\
        'Some transceivers may not work at all. You have been warned.\n'\
        '=============================================================\n'
      '' + ''
      : ''${BANNER:=}
      substitute ${./run.sh} $out/bin/$EXEC_NAME \
        --subst-var BUILD \
        --subst-var RUNTIME_ENV \
        --subst-var EXEC_NAME \
        --subst-var ARCH \
        --subst-var BANNER
        chmod a+x $out/bin/$EXEC_NAME
    '')
    );
  };
in self
