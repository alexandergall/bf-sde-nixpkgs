{ stdenv, nct6779d, kernelSpec ? null }:

stdenv.mkDerivation {
  pname = "nct6779d";
  version = "master";
  inherit (nct6779d) src patches;
  buildPhase = ''
    make KDIR=${kernelSpec.buildTree}
  '';
  installPhase = ''
    mkdir -p $out/lib/modules/${kernelSpec.kernelRelease}
    cp nct6779d.ko $out/lib/modules/${kernelSpec.kernelRelease}
  '';
}
