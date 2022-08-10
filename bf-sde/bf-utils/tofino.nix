{ pname, version, src, patches, buildSystem, lib, stdenv, cmake,
  bf-syslibs, autoconf, automake, libtool }:

stdenv.mkDerivation {
  inherit pname version patches;
  src = buildSystem.cmakeFixupSrc {
    inherit src;
    cmakeRules = ''
      include_directories(include)
    '';
  };

  buildInputs = [ cmake bf-syslibs.dev ]
                ++ lib.optionals (lib.versionAtLeast version "9.9.1")
                  [ autoconf automake libtool ];
  outputs = [ "out" "dev" ];
  installPhase = "true";
}
