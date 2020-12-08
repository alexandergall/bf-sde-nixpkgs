## Build the SDE modules for a specific kernel

{ lib, stdenv, python2, runtimeShell, kmod, callPackage, runCommand, bf-sde, spec }:

stdenv.mkDerivation {
  name = "bf-sde-${bf-sde.version}-kernel-modules-${spec.release}";

  src = bf-sde.driver_src;

  buildInputs = [ bf-sde python2 kmod ];

  buildPhase = ''
    tar xf * --strip-components 1
    mkdir $out

    mkdir build
    pushd build
    ../configure --prefix=$out enable_thrift=no \
      enable_grpc=no enable_bfrt=no enable_p4rt=no enable_pi=no --with-kdrv=yes
    echo "Kernel ${spec.release}"
    export KDIR=${spec.build}
    pushd kdrv
    make install

    mod_dir=$out/lib/modules/${spec.release}
    mkdir -p $mod_dir
    mv $out/lib/modules/*.ko $mod_dir
    popd
    popd
  '';

  installPhase = ''
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
