{ stdenv, nct6779d, kernelSpec ? null }:

let
  stdenv' = kernelSpec.stdenv or stdenv;
in stdenv'.mkDerivation {
  pname = "nct6779d";
  version = "master";
  inherit (nct6779d) src patches;
  buildInputs = kernelSpec.buildTree.inputs;
  buildPhase = ''
   . ${kernelSpec.buildTree.prep stdenv'}
    make KDIR=${kernelSpec.buildTree}
  '';
  installPhase = ''
    mkdir -p $out/lib/modules/${kernelSpec.kernelRelease}
    cp nct6779d.ko $out/lib/modules/${kernelSpec.kernelRelease}
  '';
}
