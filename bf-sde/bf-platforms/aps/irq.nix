{ stdenv, aps_irq, kernelSpec ? null }:

stdenv.mkDerivation {
  pname = "aps-bf2556-irq";
  inherit (aps_irq) src version;
  buildPhase = ''
    cd src
    make KDIR=${kernelSpec.buildTree}
  '';
  installPhase = ''
    mkdir -p $out/lib/modules/${kernelSpec.kernelRelease}
    cp *.ko $out/lib/modules/${kernelSpec.kernelRelease}
  '';
}
