{ pname, version, src, patches, buildSystem, stdenv, lib, cmake,
  autoconf, automake, libtool, glibc }:

stdenv.mkDerivation {
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

  cmakeFlags = lib.optionals buildSystem.isCmake ([
    "-DTCMALLOC=ON"
  ] ++ lib.optionals (lib.versionAtLeast version "9.9.1") [
    ## Very weird. In 9.9.0, there was a little glitch that installed
    ## libtarget_sys.so twice, once in lib and once in the package's
    ## root directory. This was fixed in 9.1.1, but then the library
    ## is deleted in the installation step. That happens because CMake
    ## generates
    ##
    ## file(RPATH_CHECK
    ##      FILE "$ENV{DESTDIR}/tmp/out/lib/libtarget_sys.so"
    ##      RPATH "")
    ##
    ## in an intermediate cmake file. This is an internal CMake call
    ## that effectively delets a file if the RPATH is not empty, which
    ## is guaranteed with Nix. This option disables that
    ## functionality.
    "-DCMAKE_SKIP_RPATH=ON"
  ]);

  buildInputs = lib.optionals buildSystem.isCmake [ cmake autoconf automake libtool ];
  outputs = [ "out" "dev" ] ++ lib.optional buildSystem.isCmake "doc";
  enableParallelBuilding = ! buildSystem.isCmake;

  preConfigure = lib.optionalString (lib.versionAtLeast glibc.version "2.34") ''
    sed -i -e 's/pthread_yield/sched_yield/' src/bf_sal/linux_usr/bf_sys_thread.c
  '';

  ## Remove pprof installed from third-party/gperftools
  postInstall = ''
    rm -rf $out/bin
  '';
}
