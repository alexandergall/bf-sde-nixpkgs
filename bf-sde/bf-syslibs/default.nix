{ pname, version, src, patches, buildSystem, stdenv, lib, cmake,
  autoconf, automake, libtool }:

stdenv.mkDerivation ({
  inherit pname version patches;
  src = buildSystem.cmakeFixupSrc {
    inherit src;
    ## Starting with 9.9.0, the syslibs component CMake build is
    ## actually self-contained.
    bypass = lib.versionAtLeast version "9.9.0";
    cmakeRules = ''
      include_directories(third-party)
      include_directories(\''${CMAKE_CURRENT_BINARY_DIR}/third-party/gperftools/src)
    '';
  };

  buildInputs = lib.optional buildSystem.isCmake [ cmake autoconf automake libtool ];
  outputs = [ "out" "dev" ] ++ lib.optional buildSystem.isCmake "doc";
  enableParallelBuilding = ! buildSystem.isCmake;

  ## Remove pprof installed from third-party/gperftools
  postInstall = ''
    rm -rf $out/bin
  '';
} //   lib.optionalAttrs buildSystem.isCmake {
  ## Attributes that did not exist in pre-cmake builds are added here
  ## for cmake builds only to avoid re-building of the autoconf-based
  ## packages. The empty attributes would not change the result of
  ## builds but cause the out paths to change.
  cmakeFlags = [ "-DTCMALLOC=ON" ];
})
