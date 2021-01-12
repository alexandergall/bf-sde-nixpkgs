{ pname, version, src, patches, stdenv }:

stdenv.mkDerivation {
  inherit pname version src patches;

  outputs = [ "out" "dev" ];
  enableParallelBuilding = true;

  ## Remove pprof installed from third-party/gperftools
  postInstall = ''
    rm -rf $out/bin
  '';
}
