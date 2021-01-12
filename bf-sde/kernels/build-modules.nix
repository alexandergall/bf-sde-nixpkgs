## Build the SDE modules for a specific kernel

{ lib, stdenv, python2, runtimeShell, kmod,
  version, src, spec, bf-syslibs }:

stdenv.mkDerivation {
  name = "bf-sde-${version}-kernel-modules-${spec.release}";
  inherit src;

  patches = lib.optionals (spec.patches ? ${version})
                          spec.patches.${version};
  buildInputs = [ bf-syslibs python2 kmod ];
  configureFlags = [
    " --with-kdrv=yes"
    "enable_thrift=no"
    "enable_grpc=no"
    "enable_bfrt=no"
    "enable_p4rt=no"
    "enable_pi=no"
  ];
  KDIR = "${spec.build}";

  preBuild = ''
    cd kdrv
  '';

  postInstall = ''
    mod_dir=$out/lib/modules/${spec.release}
    mkdir -p $mod_dir
    mv $out/lib/modules/*.ko $mod_dir

    for mod in kpkt kdrv knet; do
      script=$out/bin/bf_''${mod}_mod_load
      substituteInPlace  $script \
        --replace lib/modules "lib/modules/\$(uname -r)" \
        --replace insmod ${kmod}/bin/insmod
      substituteInPlace $out/bin/bf_''${mod}_mod_unload \
        --replace rmmod ${kmod}/bin/rmmod
      mv $script ''${script}.wrapped
      echo '#!${runtimeShell}' >>$script
      echo "$script.wrapped $out" >>$script
      chmod a+x $script
    done
  '';
}
