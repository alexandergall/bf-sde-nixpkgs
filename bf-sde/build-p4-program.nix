{ stdenv, lib, bf-sde, getopt, which, coreutils, findutils,
  procps, gnugrep, gnused, utillinux, runtimeShell }:

{ name ? attrs.${name},
  version ? attrs.${version},
# The name of the p4 program to compile without the ".p4" extension
  p4Name ? attrs.${p4Name},
# The path to the program relative to the root of the source tree.
# I.e. the program to be compiled si expected to be
#   <path>/<p4Name>.p4
  path ? null,
# The flags passed to the p4_build.sh script
  buildFlags ? "",
  src ? attrs.${src},
} @attrs:

stdenv.mkDerivation rec {
  buildInputs = [ bf-sde getopt which procps ];

  inherit (attrs) name version src p4Name;
  
  buildPhase = ''
    set -e
    export SDE=${bf-sde}
    export SDE_INSTALL=$SDE
    export P4_INSTALL=$out
    export SDE_BUILD=$TEMP
    export SDE_LOGS=$TEMP
    mkdir $out
    cmd="${bf-sde}/bin/p4_build.sh ${buildFlags} ${if path == null then "." else path}/${p4Name}.p4"
    echo "Build command: $cmd"
    $cmd
  '';

  installPhase = ''

    ## This script will execute bf_switchd with our P4 program
    command=$out/bin/${p4Name}
    mkdir $out/bin
    cat <<EOF > $command
    #!${runtimeShell}
    export SDE=${bf-sde}
    export SDE_INSTALL=${bf-sde}
    export P4_INSTALL=$out

    ## We would like to make this self-contained with nixpkgs, but
    ## sudo is a special case because suid executables are not
    ## supported. Hence we use sudo from /usr/bin for the time being.
    export PATH=${lib.strings.makeBinPath [ coreutils findutils gnugrep gnused utillinux procps ]}:/usr/bin
    ${bf-sde}/run_switchd.sh -p ${p4Name}
    EOF
    chmod a+x $command

    ## Create links to bfshell and the kernel module load/unload scripts for convenience
    ln -s ${bf-sde}/bin/bfshell $out/bin
    for mod in kdrv knet kpkt; do
      name=bf_''${mod}_mod
      ln -s ${bf-sde}/bin/''${name}_unload $out/bin/''${name}_unload
      load=$out/bin/''${name}_load
      echo '#!${runtimeShell}' >>$load
      echo "${bf-sde}/bin/''${name}_load ${bf-sde}" >>$load
      chmod a+x $load
    done
  '';
}
