## Build the SDE modules for a specific kernel

{ lib, stdenv, buildEnv, python2, runtimeShell, kmod, coreutils,
  version, buildSystem, src, kernelID, spec, bf-syslibs, cmake,
  drvsWithKernelModules }:

let
  driverModules = stdenv.mkDerivation ({
    name = "bf-sde-${version}-kernel-modules-${spec.kernelRelease}";
    src = buildSystem.cmakeFixupSrc {
      inherit src;
      ## Only copy the cmake directory from the top-level. The driver
      ## package is not really self-contained even in standalone mode.
      preambleOverride = true;
    };

    passthru = {
      inherit kernelID;
      inherit (spec) kernelRelease;
    };

    patches = (spec.patches.all or []) ++
              (spec.patches.${version} or []);
    buildInputs = [ bf-syslibs python2 kmod ]
                  ++ lib.optional buildSystem.isCmake [ cmake ];

    configureFlags = lib.optional (! buildSystem.isCmake) [
      " --with-kdrv=yes"
      "enable_thrift=no"
      "enable_grpc=no"
      "enable_bfrt=no"
      "enable_p4rt=no"
      "enable_pi=no"
    ];
    KDIR = "${spec.buildTree}";

    preBuild = lib.optionalString (! buildSystem.isCmake) ''
      cd kdrv
    '';

    postInstall = lib.optionalString buildSystem.isCmake ''
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
  } // lib.optionalAttrs (buildSystem.isCmake) {
    cmakeFlags = [
        "-DSTANDALONE=ON"
        "-DTHRIFT-DRIVER=OFF"
        "-DGRPC=OFF"
        "-DBFRT=OFF"
        "-DPI=OFF"
        "-DP4RT=OFF"
        ## Enable building of kdrv
        "-DASIC=ON"
        "-DKDIR=${spec.buildTree}"
    ];
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
  });
in buildEnv {
  name = "bf-sde-${version}-combined-kernel-modules-${spec.kernelRelease}";
  paths = [ driverModules ] ++
          map (drv: drv.override { kernelSpec = spec; }) drvsWithKernelModules;
  inherit (driverModules) passthru;
}
