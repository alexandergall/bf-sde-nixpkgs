## Build the SDE modules for a specific kernel

{ lib, stdenv, python2, runtimeShell, kmod, coreutils, version,
  buildSystem, src, kernelID, spec, bf-syslibs, cmake }:

stdenv.mkDerivation ({
  name = "bf-sde-${version}-kernel-modules-${spec.kernelRelease}";
  inherit src;

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

    wrap () {
    cat <<EOF >> $1
    #!${runtimeShell}
    kernelRelease=\$(${coreutils}/bin/uname -r)
    if [ \$kernelRelease != ${spec.kernelRelease} ]; then
      echo "\$0: expecting kernel ${spec.kernelRelease}, got \$kernelRelease, aborting"
      exit 1
    fi
    exec $1.wrapped $out
    EOF
    }

    for mod in kpkt kdrv knet; do
      script=$out/bin/bf_''${mod}_mod_load
      substituteInPlace  $script \
        --replace lib/modules "lib/modules/\$(${coreutils}/bin/uname -r)" \
        --replace insmod ${kmod}/bin/insmod
      substituteInPlace $out/bin/bf_''${mod}_mod_unload \
        --replace rmmod ${kmod}/bin/rmmod
      mv $script ''${script}.wrapped
      wrap $script
      chmod a+x $script
    done
  '';
} // lib.optionalAttrs (buildSystem.isCmake) {
  cmakeFlags = [
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
  preConfigure = buildSystem.preConfigure {
    package = "bf-drivers";
    cmakeRules = ''
      find_package(Thrift REQUIRED)
      include_directories(''${BF_PKG_DIR}/bf-drivers)
      include_directories(''${BF_PKG_DIR}/bf-drivers/include)
      add_subdirectory(''${BF_PKG_DIR}/bf-drivers)
    '';
  };
  installPhase = ''
    (cd pkgsrc/bf-drivers/kdrv && make install)
    for dir in bf_kdrv bf_knet bf_kpkt; do
      (cd pkgsrc/bf-drivers/kdrv/$dir && make install)
    done
    runHook postInstall
  '';
})
