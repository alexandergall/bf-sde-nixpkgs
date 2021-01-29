{ lib, writeShellScriptBin, kmod, gawk, gnugrep, modules, execName, requiredKernelModule, self }:

writeShellScriptBin "${execName}-module-wrapper"
  ''
    set -e

    export PATH=${lib.strings.makeBinPath [ gawk gnugrep kmod ]}:${self}/mock-sudo

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

    exec ${self}/bin/${execName} "$@"
  ''
