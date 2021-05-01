{ stdenv, callPackage, lib, bf-sde, runtimeEnv, runtimeShell }:

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
# The kernel module required by bf_switchd for this program, one
# of bf_kdrv, bf_kpkt, bf_knet. Used by the makeModuleWrapper
# support function to load the module before executing bf_switchd.
  requiredKernelModule ? null,
# The flags passed to the p4_build.sh script
  buildFlags ? [],
  src,
# Optional patches
  patches ? [],
# Optional derivation overrides. They need to be applied here in
# order to make the overridden derivation visibile to the
# makeModuleWrapper passthru function
  overrides ? {}
}:

assert requiredKernelModule != null -> lib.any (e: requiredKernelModule == e)
                                               [ "bf_kdrv" "bf_kpkt" "bf_knet" ];

let
  passthru = {
    ## Preserve the name of the program. Used by the test.cases
    ## attribute of the sde package.
    inherit p4Name;

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
        ## Re-create the patched source tree to execercise
        ## the PTF tests
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

  self = (stdenv.mkDerivation rec {
    buildInputs = [ bf-sde ];

    inherit pname version src p4Name patches buildFlags passthru;

    buildPhase = ''
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
      cmd="${bf-sde}/bin/p4_build.sh $buildFlags $path/$exec_name.p4"
      echo "Build command: $cmd"
      $cmd
    '';

    installPhase = ''

      mkdir $out/bin

      ## This script executes bf_switchd via the run_switchd.sh
      ## wrapper with our P4 program artifacts.
      command=$out/bin/$exec_name
      cat <<EOF > $command
      #!${runtimeShell}
      set -e

      if [ -n "\$1" ]; then
        cd \$1
      fi

      export P4_INSTALL=$out
      exec ${runtimeEnv}/bin/run_switchd.sh -p $exec_name
      EOF
      chmod a+x $command
      runHook postInstall
    '';
  }).overrideAttrs (_: overrides );
in self
