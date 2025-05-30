{ pname, version, src, patches, stdenv, cmake, target-syslibs, libedit, expat }:

stdenv.mkDerivation {
  inherit pname version src patches;
  nativeBuildInputs = [ cmake target-syslibs libedit expat ];
  outputs = [ "out" "dev" ];
}
