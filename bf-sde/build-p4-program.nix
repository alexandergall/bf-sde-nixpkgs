{ stdenv, callPackage, lib, bf-sde, runtimeEnv, getopt, which, coreutils,
  gnugrep, gnused, procps, utillinux, findutils, bash, runtimeShell, python2 }:

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
  buildFlags ? "",
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
  makeModuleWrapper' = { modules }:
    if requiredKernelModule != null then
      callPackage ./modules-wrapper.nix {
        inherit modules execName requiredKernelModule self;
      }
    else
      throw "${pname} does not require a kernel module";

  passthru = {
    ## Preserve the name of the program. Used by the test.cases
    ## attribute of the sde package.
    inherit p4Name;

    ## Build a shell script to load the required kernel module for a given
    ## kernel before executing the program.
    ## Used by release.nix to pre-build wrappers for all kernels
    makeModuleWrapperForKernel = kernelID:
      makeModuleWrapper' { modules = bf-sde.buildModules kernelID; };
    ## Build the wrapper for the running system
    makeModuleWrapper = makeModuleWrapper' {
      modules = bf-sde.buildModulesForLocalKernel;
    };
    runTest = args:
      let
        ## Re-create the patched source tree to execercise
        ## the PTF tests
        src' = stdenv.mkDerivation {
          name = "${pname}-${version}-source";
          inherit src patches;
          configurePhase = "true";
          buildPhase = "true";
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
    buildInputs = [ bf-sde getopt which procps python2 ];

    inherit pname version src p4Name patches passthru;

    buildPhase = ''
      set -e
      export SDE=${bf-sde}
      export SDE_INSTALL=$SDE
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
      cmd="${bf-sde}/bin/p4_build.sh ${buildFlags} $path/$exec_name.p4"
      echo "Build command: $cmd"
      $cmd
    '';

    installPhase = ''

      mkdir $out/bin

      ## This script executes bf_switchd via the run_switchd.sh
      ## wrapper with our P4 program artifacts.
      ##
      ## The run_switchd.sh script uses sudo to perform some
      ## privileged operations. This is ok and useful if it is
      ## executed by a user in a SDE shell, for example.  sudo itself
      ## is not part of nixpkgs, because setuid semantics are not
      ## supported (NixOS uses a special wrapper mechanism to solve
      ## this problem). OTOH, we don't want to introduce an impurity
      ## in this derivation by using the system's sudo.
      ##
      ## What we do instead is to create a pseudo sudo script which
      ## simply terminates with an error if not run as root and
      ## executes the given command without sudo if run as root.
      mkdir $out/mock-sudo
      cat <<EOF > $out/mock-sudo/sudo
      #!${runtimeShell}
      if [ \$(${coreutils}/bin/id -u) -ne 0 ]; then
        echo "Please run this command as root"
        exit 1
      fi
      exec "\$@"
      EOF
      chmod a+x $out/mock-sudo/sudo

      command=$out/bin/$exec_name
      cat <<EOF > $command
      #!${runtimeShell}
      set -e

      export SDE=${runtimeEnv}
      export SDE_INSTALL=\$SDE
      export P4_INSTALL=$out

      export PATH=${lib.strings.makeBinPath [ coreutils gnugrep gnused utillinux procps findutils bash ]}:$out/mock-sudo

      ## Force failure if not run as root
      sudo true

      if [ -n "\$1" ]; then
        cd \$1
      fi
      exec ${runtimeEnv}/bin/run_switchd.sh -p $exec_name
      EOF
      chmod a+x $command
      runHook postInstall
    '';
  }).overrideAttrs (_: overrides );
in self
