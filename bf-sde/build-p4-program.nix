{ stdenv, lib, bf-sde, getopt, which, coreutils, findutils,
  procps, gnugrep, gnused, gawk, kmod, utillinux, runtimeShell }:

{ name,
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
# The kernel module to load before launching bf_switchd. Must be one
# of bf_kdrv, bf_kpkt, bf_knet
  kernelModule ? null,
# The flags passed to the p4_build.sh script
  buildFlags ? "",
  src
}:

assert kernelModule != null -> lib.any (e: kernelModule == e) [ "bf_kdrv" "bf_kpkt" "bf_knet" ];

stdenv.mkDerivation rec {
  buildInputs = [ bf-sde getopt which procps ];

  inherit name version src p4Name;
  
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
    export PATH=${lib.strings.makeBinPath [ coreutils findutils gnugrep gnused gawk kmod utillinux procps ]}:/usr/bin
  '' + (lib.optionalString (kernelModule != null)
  ''

    function mod_exists {
      lsmod | awk '{print $1}' | grep \$1 >/dev/null
    }

    for mod in bf_kdrv bf_knet bf_kpkt; do
      [ \''${mod} == ${kernelModule} ] && continue
      if mod_exists \''${mod}; then
        echo "Unloading \''${mod}"
        sudo ${bf-sde}/bin/\''${mod}_mod_unload
      fi
    done
    if ! mod_exists ${kernelModule}; then
      echo "Loading ${kernelModule}"
      sudo ${bf-sde}/bin/${kernelModule}_mod_load
    fi
  '') +
  ''
    ${bf-sde}/run_switchd.sh -p $exec_name
    EOF
    chmod a+x $command
  '';
}
