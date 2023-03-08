{ stdenv, aps_igb, kernelSpec ? null }:

stdenv.mkDerivation {
  pname = "aps-bf6064-igb";
  inherit (aps_igb) src version;
  buildPhase = ''
    cd src
    sed -i -e 's/read_barrier_depends/smp_rmb/' igb_main.c
    make KDIR=${kernelSpec.buildTree}
  '';
  installPhase = ''
    mkdir -p $out/lib/modules/${kernelSpec.kernelRelease}
    cp *.ko $out/lib/modules/${kernelSpec.kernelRelease}
  '';
}
