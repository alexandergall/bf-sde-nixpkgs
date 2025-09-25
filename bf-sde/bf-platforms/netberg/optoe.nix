{ lib, stdenv, kernelSpec ? null, fetchFromGitHub }:

let
  stdenv' = kernelSpec.stdenv or stdenv;
in stdenv'.mkDerivation {
  name = "netberg-optoe-kmod";
  src = fetchFromGitHub {
    owner  = "opencomputeproject";
    repo   = "oom";
    rev    = "b7cc8c1";
    sha256 = "0lq7ws9c8b8d5p2zn7wr6vpyxr0pyai557awzm34phdxd28vr8cd";
  };
  buildInputs = kernelSpec.buildTree.inputs;
  patches = [ ./optoe-nvmem.patch ./optoe-driver.patch ];
  NIX_CFLAGS_COMPILE = lib.optional (lib.versionAtLeast kernelSpec.kernelRelease "5.0")
    "-DLATEST_KERNEL";
  buildPhase = ''
    . ${kernelSpec.buildTree.prep stdenv'}
    sdir=$(realpath optoe)
    echo "obj-m += optoe.o" >optoe/Makefile
    make -C ${kernelSpec.buildTree} M=$sdir src=$sdir
  '';
  installPhase = ''
    dir=$out/lib/modules/${kernelSpec.kernelRelease}
    mkdir -p $dir
    cp optoe/optoe.ko $dir
  '';
}
