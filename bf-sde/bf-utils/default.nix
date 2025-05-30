{ pname, version, src, patches, stdenv, buildSupport, cmake,
  target-syslibs, autoconf, automake, libtool }:

stdenv.mkDerivation {
  inherit pname version patches;
  src = buildSupport.fixupSrc {
    inherit src;
    cmakeRules = ''
      include_directories(include)
    '';
  };

  nativeBuildInputs = [ cmake target-syslibs autoconf automake libtool ];
  outputs = [ "out" "dev" ];
  installPhase = "true";
}
