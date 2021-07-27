{ pname, version, src, patches, buildSystem, stdenv, lib, cmake,
  autoconf, automake, libtool }:

stdenv.mkDerivation ({
  inherit pname version src patches;

  buildInputs = lib.optional buildSystem.isCmake [ cmake autoconf automake libtool ];
  outputs = [ "out" "dev" ] ++ lib.optional buildSystem.isCmake "doc";
  enableParallelBuilding = ! buildSystem.isCmake;

  ## Remove pprof installed from third-party/gperftools
  postInstall = ''
    rm -rf $out/bin
  '';
} // lib.optionalAttrs (buildSystem.isCmake) {
  preConfigure = buildSystem.preConfigure {
    package = "bf-syslibs";
    cmakeRules = ''
      include_directories(''${BF_PKG_DIR}/bf-syslibs/include)
      include_directories(''${BF_PKG_DIR}/bf-syslibs/third-party)
      add_subdirectory(''${BF_PKG_DIR}/bf-syslibs)
    '';
  };
})
