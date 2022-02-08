{ stdenv, callPackage, procps, kmod, lib, buildEnv, coreutils, gnused,
  gnugrep, bf-sde }:

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
# Build target
  target ? "tofino",
# The flags passed to the p4_build.sh script
  buildFlags ? [],
  src,
# Optional patches
  patches ? []
}:

assert requiredKernelModule != null -> lib.assertOneOf "kernel module"
  requiredKernelModule [ "bf_kdrv" "bf_kpkt" "bf_knet" ];

assert lib.assertOneOf "platform" platform (builtins.attrNames (import
  ../bf-platforms/properties.nix));

assert lib.assertOneOf "target" target [ "tofino" "tofino2" ];

let
  targetFlag = {
    tofino = "-DTOFINO=ON";
    tofino2 = "-DTOFINO2=ON";
  }.${target};

  runtimeEnv = bf-sde.runtimeEnv' platform;

  ## The SAL wrapper for the aps_bf2556 platform currently requires
  ## that the build artifacts are located in the runtime environment.
  runtimeEnvWithArtifacts = buildEnv {
    name = runtimeEnv.name + "-${p4Name}-artifacts";
    paths = [ runtimeEnv build ];
  };

  passthru = {
    inherit p4Name target;

    ## Build a shell script to load the required kernel module for a given
    ## kernel before executing the program.
    moduleWrapper' = modules:
      callPackage ./modules-wrapper.nix {
        inherit execName requiredKernelModule modules self;
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
        inherit self p4Name bf-sde;
        src = src';
        ## Default directory of PTF test scripts relative to
        ## the source tree
        testDir = path;
      } // args);
  };

  ## Create a separate derivation for the P4 artifacts that does not
  ## depend on the runtime environment (i.e. on the platform).
  build = stdenv.mkDerivation {
    buildInputs = [ bf-sde ];
    pname = "${execName}-artifacts";
    inherit version src p4Name patches buildFlags;

    buildPhase = if lib.versionOlder bf-sde.version "9.7.0" then ''
      set -e
      export P4_INSTALL=$out
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
    '' else
    ''
      set -e
      export P4_INSTALL=$out
      echo "Building \"${p4Name}.p4\" as \"${execName}\" for target \"${target}\" with p4c flags \"$buildFlags\""
      ${bf-sde}/bin/p4_build.sh --p4-name=${execName} --p4c-flags="$buildFlags" \
        --cmake-flags ${targetFlag} $(realpath ${path}/${p4Name}.p4)
      rm -rf $out/build
    '';

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
          --subst-var-by pkill ${procps}/bin/pkill \
          --subst-var-by rmmod ${kmod}/bin/rmmod
        chmod a+x $out/bin/$EXEC_NAME
      '';
      stordis_bf2556x_1t = ''
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
    }.${platform} or ''
      substitute ${./run.sh} $out/bin/$EXEC_NAME \
        --subst-var BUILD \
        --subst-var RUNTIME_ENV \
        --subst-var EXEC_NAME \
        --subst-var ARCH
        chmod a+x $out/bin/$EXEC_NAME
    '');
  };
in self
