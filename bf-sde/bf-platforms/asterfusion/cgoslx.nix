{ lib, stdenv, cgoslx, kernelSpec ? null }:

let
  stdenv' = kernelSpec.stdenv or stdenv;
in stdenv'.mkDerivation {
  pname = "cgoslx";
  version = "master";
  inherit (cgoslx) src patches;
  KMOD = kernelSpec != null;
  KERNELDIR = lib.optionalString (kernelSpec != null)
    kernelSpec.buildTree;
  buildInputs = lib.optionals (kernelSpec != null) kernelSpec.buildTree.inputs;
  buildPhase = lib.optionalString (kernelSpec != null) ''
    . ${kernelSpec.buildTree.prep stdenv'}
  '' + ''
    export KMOD
    export KERNELDIR
    make
  '';
  installPhase = lib.optionalString (kernelSpec != null) ''
    if [ -n "$KMOD" ]; then
      export KMOD_INSTALL=$out/lib/modules/${kernelSpec.kernelRelease}
    fi
  '' + ''
    export PREFIX=$prefix
    make install
  '';
}
