{ lib, writeShellScriptBin, kmod, gawk, gnugrep, modules, execName, requiredKernelModule, derivation }:

writeShellScriptBin "${execName}-module-wrapper"
  ''
    set -e

    ## Include /usr/bin for sudo
    export PATH=${lib.strings.makeBinPath [ gawk gnugrep kmod ]}:/usr/bin

    function mod_exists {
        lsmod | awk '{print $1}' | grep $1 >/dev/null
    }

    for mod in bf_kdrv bf_knet bf_kpkt; do
        [ ''${mod} == ${requiredKernelModule} ] && continue
        if mod_exists ''${mod}; then
          echo "Unloading ''${mod}"
          sudo ${modules}/bin/''${mod}_mod_unload
        fi
    done
    if ! mod_exists ${requiredKernelModule}; then
        echo "Loading ${requiredKernelModule}"
        sudo ${modules}/bin/${requiredKernelModule}_mod_load
    fi

    exec ${derivation}/bin/${execName} "$@"
  ''
