{ lib, writeShellScriptBin, kmod, gawk, gnugrep, coreutils, modules,
  execName, requiredKernelModule, self, bf-sde }:

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

  '' + ({
    newport = ''
      if ! mod_exists bf_fpga; then
        echo "Loading bf_fpga for Newport baseboard"
        /usr/bin/sudo ${modules}/bin/bf_fpga_mod_load
      fi
    '';
    inventec = ''
      mdir=${modules}/lib/modules/${modules.kernelRelease}
      if [ -e $mdir/.inventec-unsupported ]; then
        echo "Kernel ${modules.kernelRelease} is not supported for the Inventec baseboard"
        exit 1
      fi
      echo "Loading additional kernel modules"
      /usr/bin/sudo modprobe i2c-mux
      for mod in i2c-mux-pca954x gpio-ich inv_cpld inv_eeprom  inv_psoc vpd inv_platform swps; do
        file=$mdir/$mod.ko
        echo $file
        /usr/bin/sudo insmod $file || true
      done
    '';
    netberg_710 = ''
      export MODULES=${modules}/lib/modules/${modules.kernelRelease}
      echo "De-initializing I2C for Netberg Aurora 710"
      /usr/bin/sudo --preserve-env=MODULES ${modules}/bin/i2c_utils.sh i2c_deinit
      echo "Initializing I2C for Netberg Aurora 710"
      /usr/bin/sudo --preserve-env=MODULES ${modules}/bin/i2c_utils.sh i2c_init
    '';
    asterfusion = ''
      export MODULES=${modules}
      ${builtins.getAttr self.baseboard bf-sde.pkgs.bf-platforms}/bin/xt-cfgen.sh
    '';
  }.${if self.baseboard != null then self.baseboard else ""} or "") + ''
    exec ${self}/bin/${execName} "$@"
  ''
   else ''
    exec ${self}/bin/${execName} "$@"
  '')
).overrideAttrs (_: {
  passthru = {
    inherit modules;
  };
})
