## Build the SDE modules for a specific kernel

{ lib, stdenv, buildEnv, python3, runtimeShell, kmod,
  coreutils, version, buildSupport, src, kernelID, spec, target-syslibs,
  cmake, drvsWithKernelModules, baseboard ? null }:

assert lib.assertMsg (baseboard != null -> ! builtins.elem baseboard spec.baseboardBlacklist)
  "baseboard ${baseboard} is blacklisted for kernel ${kernelID}";
let
  baseboard' = if baseboard == null then "" else baseboard;
  stdenv' = spec.stdenv or stdenv;
  driverModules = stdenv'.mkDerivation {
    name = "bf-sde-${version}-kernel-modules-${spec.kernelRelease}";
    src = buildSupport.fixupSrc {
      inherit src;
      ## Only copy the cmake directory from the top-level. The driver
      ## package is not really self-contained even in standalone mode.
      preambleOverride = true;
    };

    passthru = {
      inherit kernelID;
      inherit (spec) kernelRelease baseboardBlacklist;
    };

    patches = (spec.patches.all or []) ++
              (spec.patches.${version} or []);
    buildInputs = [ cmake target-syslibs python3 kmod ];

    preConfigure = ''
      sed -i '/project/a list(APPEND CMAKE_MODULE_PATH "\''${CMAKE_CURRENT_SOURCE_DIR}/cmake")' CMakeLists.txt
    '';

    KDIR = "${spec.buildTree}";

    cmakeFlags = [
        "-DSTANDALONE=ON"
        "-DTHRIFT-DRIVER=OFF"
        "-DGRPC=OFF"
        "-DBFRT=OFF"
        "-DPI=OFF"
        "-DP4RT=OFF"
        ## Enable building of kdrv
        "-DKERNEL-MODULES=ON"
        "-DKDIR=${spec.buildTree}"
    ];

    ## Make gcc recognise the pseudo comment "FALLTHRU"
    NIX_CFLAGS_COMPILE= [ "-Wimplicit-fallthrough=4" ];

    buildFlags = [
      "bf_kdrv"
      "bf_knet"
      "bf_kpkt"
    ];

    installPhase = ''
      (cd kdrv && make install)
      for dir in bf_kdrv bf_knet bf_kpkt; do
        (cd kdrv/$dir && make install)
      done
      runHook postInstall
    '';

    postInstall = ''
      ## Cmake installs a bunch of files directly, i.e.
      ## not as part of any install targets. We can only
      ## get rid of them once all passes of "make" have
      ## completed.
      shopt -s extglob
      rm -rf $out/include $out/share $out/bin/!(bf_*) $out/lib/!(modules)
      shopt -u extglob
    '' + ''
      mod_dir=$out/lib/modules/${spec.kernelRelease}
      mkdir -p $mod_dir
      mv $out/lib/modules/*.ko $mod_dir
    '' + import ./fixup-mod-loaders.nix {
      inherit (spec) kernelRelease;
      inherit runtimeShell kmod coreutils;
    };
  };
  selectDefaultOrBaseboard = attrs: baseboard:
    lib.filterAttrs (attr: _: attr == "default" || attr == baseboard) attrs;
  additionalKernelModules = lib.optionals (spec ? additionalModules)
    (assert lib.assertMsg (spec.buildTree ? source)
      "kernel flavor for ${spec.kernelRelease} does not support building additional modules";
      let
        build = { directory, makeFlags }:
          ''
            make -C ${spec.buildTree} M=$(realpath ${directory}) ${builtins.concatStringsSep " " makeFlags}
          '';
        install = { directory, makeFlags }:
          ''
            cp $(realpath ${directory})/*.ko $dest
          '';
        buildDrv = name: modSpecs:
          stdenv'.mkDerivation {
            name = "additional-kernel-modules-${name}";
            src = spec.buildTree.source;
            buildPhase = map build modSpecs;
            installPhase = ''
              dest=$out/lib/modules/${spec.kernelRelease}
              mkdir -p $dest
            '' + builtins.concatStringsSep "\n" (map install modSpecs);
          };
      in lib.mapAttrsToList buildDrv
        (selectDefaultOrBaseboard spec.additionalModules baseboard')
    );
in
if kernelID == "none" then
  ## Create a dummy modules package which exits with an error when
  ## attempting to load a module.
  stdenv.mkDerivation {
    name = "bf-sde-unsupported-kernel";
    passthru = {
      inherit kernelID;
      inherit (spec) kernelRelease baseboardBlacklist;
    };
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/bin
      for mod in kpkt kdrv knet; do
        load_cmd=$out/bin/bf_''${mod}_mod_load
        cat <<"EOF" >$load_cmd
      #!${runtimeShell}
      echo "No modules available for this kernel"
      exit 1
      EOF
      chmod a+x $load_cmd
      cp $load_cmd $out/bin/bf_''${mod}_mod_unload
      done
    '';
  }
else
  buildEnv {
    name = "bf-sde-${version}-combined-kernel-modules-${spec.kernelRelease}"
           + lib.optionalString (baseboard' != "") "-${baseboard'}";
    paths = [ driverModules ] ++ additionalKernelModules ++
            map (drv: drv.override { kernelSpec = spec; })
              (lib.flatten (builtins.attrValues
                (selectDefaultOrBaseboard drvsWithKernelModules baseboard')));
    inherit (driverModules) passthru;
  }
