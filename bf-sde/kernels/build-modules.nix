## Build the SDE modules for a specific kernel

{ lib, stdenv, python2, runtimeShell, kmod, coreutils,
  version, src, kernelID, spec, bf-syslibs }:

stdenv.mkDerivation {
  name = "bf-sde-${version}-kernel-modules-${spec.kernelRelease}";
  inherit src;

  passthru = {
    inherit kernelID;
    inherit (spec) kernelRelease;
  };

  patches = (spec.patches.all or []) ++
            (spec.patches.${version} or []);
  buildInputs = [ bf-syslibs python2 kmod ];
  configureFlags = [
    " --with-kdrv=yes"
    "enable_thrift=no"
    "enable_grpc=no"
    "enable_bfrt=no"
    "enable_p4rt=no"
    "enable_pi=no"
  ];
  KDIR = "${spec.buildTree}";

  preBuild = ''
    cd kdrv
  '';

  postInstall = ''
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
}
