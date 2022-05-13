{ pname, version, src, patches, buildSystem, stdenv, cmake, bf-syslibs }:

stdenv.mkDerivation {
  inherit pname version patches;
  src = buildSystem.cmakeFixupSrc {
    inherit src;
    cmakeRules = ''
      include_directories(include)
    '';
  };

  buildInputs = [ cmake bf-syslibs.dev ];
  outputs = [ "out" "dev" ];
  installPhase = "true";
}
