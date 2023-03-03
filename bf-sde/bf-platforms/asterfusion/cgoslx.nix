{ lib, stdenv, cgoslx, kernelSpec ? null }:

stdenv.mkDerivation {
  pname = "cgoslx";
  version = "master";
  inherit (cgoslx) src patches;
  KMOD = kernelSpec != null;
  KERNELDIR = lib.optionalString (kernelSpec != null)
    kernelSpec.buildTree;
  buildPhase = ''
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
