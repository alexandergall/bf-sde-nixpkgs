{ lib, writeShellScriptBin, kmod, gawk, gnugrep, modules, execName,
  requiredKernelModule, self }:

## Build a dummy wrapper if no kernel module is required by the
## program in order to treat all programs the same.
(writeShellScriptBin "${execName}-module-wrapper"
  (if (requiredKernelModule != null) then ''
    set -e

    export PATH=${lib.strings.makeBinPath [ gawk gnugrep kmod ]}

    function mod_exists {
        lsmod | awk '{print $1}' | grep $1 >/dev/null
    }

    for mod in bf_kdrv bf_knet bf_kpkt; do
        [ ''${mod} == ${requiredKernelModule} ] && continue
        if mod_exists ''${mod}; then
          echo "Unloading ''${mod}"
          /usr/bin/sudo ${modules}/bin/''${mod}_mod_unload
        fi
    done
    if ! mod_exists ${requiredKernelModule}; then
        echo "Loading ${requiredKernelModule}"
        /usr/bin/sudo ${modules}/bin/${requiredKernelModule}_mod_load
    fi

    exec ${self}/bin/${execName} "$@"
  ''
    ## Make sure no module is loaded if none is required. This is
    ## mainly to avoid crashes of bf_switchd that have been observed
    ## when running on the model while a kernel module is loaded.
   else ''
    for mod in bf_kdrv bf_knet bf_kpkt; do
        if mod_exists ''${mod}; then
          echo "Unloading ''${mod}"
          /usr/bin/sudo ${modules}/bin/''${mod}_mod_unload
        fi
    done

    exec ${self}/bin/${execName} "$@"
  '')
).overrideAttrs (_: {
  passthru = {
    inherit modules;
  };
})
