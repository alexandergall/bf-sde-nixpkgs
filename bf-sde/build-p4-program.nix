{ stdenv, callPackage, lib, bf-sde, getopt, which, coreutils, gnugrep,
  gnused, procps, utillinux, runtimeShell }:

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
# Optional derivation overrides. They need to be applied here in
# order to make the overridden derivation visibile to the
# makeModuleWrapper passthru function
  overrides ? {}
}:

assert requiredKernelModule != null -> lib.any (e: requiredKernelModule == e)
                                               [ "bf_kdrv" "bf_kpkt" "bf_knet" ];

let
  passthru = {
    ## Build a shell script to load the required kernel module for the
    ## current system before executing the program.
    makeModuleWrapper =
      if requiredKernelModule != null then
        callPackage ./modules-wrapper.nix {
          modules = bf-sde.buildModulesForLocalKernel;
          inherit execName requiredKernelModule self;
        }
      else
        throw "${pname} does not require a kernel module";
  };
  self = (stdenv.mkDerivation rec {
    buildInputs = [ bf-sde getopt which procps ];

    inherit pname version src p4Name passthru;

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

      ## This script will execute bf_switchd with our P4 program
      command=$out/bin/$exec_name
      mkdir $out/bin
      cat <<EOF > $command
      #!${runtimeShell}
      export SDE=${bf-sde}
      export SDE_INSTALL=${bf-sde}
      export P4_INSTALL=$out

      ## We would like to make this self-contained with nixpkgs, but
      ## sudo is a special case because suid executables are not
      ## supported. Hence we use sudo from /usr/bin for the time being.
      export PATH=${lib.strings.makeBinPath [ coreutils gnugrep gnused utillinux procps ]}:/usr/bin

      if [ -n "\$1" ]; then
        cd \$1
      fi
      exec ${bf-sde}/bin/run_switchd.sh -p $exec_name
      EOF
      chmod a+x $command
      runHook postInstall
    '';
  }).overrideAttrs (_: overrides );
in self
