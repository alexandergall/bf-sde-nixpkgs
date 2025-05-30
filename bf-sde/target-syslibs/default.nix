{ pname, version, src, patches, stdenv, cmake, autoconf, automake,
  libtool }:

stdenv.mkDerivation {
  inherit pname version src patches;

  cmakeFlags = [
    "-DTCMALLOC=ON"

    ## By default, libtarget_sys.so is deleted in the installation
    ## step.  That happens because CMake generates
    ##
    ## file(RPATH_CHECK
    ##      FILE "$ENV{DESTDIR}/tmp/out/lib/libtarget_sys.so"
    ##      RPATH "")
    ##
    ## in an intermediate cmake file. This is an internal CMake call
    ## that effectively delets a file if the RPATH is not empty, which
    ## is guaranteed with Nix. This option disables that
    ## functionality.
    ### TODO
    "-DCMAKE_SKIP_RPATH=ON"
  ];

  buildInputs = [ cmake autoconf automake libtool ];
  outputs = [ "out" "dev" "doc" ];

  preConfigure =
    ## The target-syslibs component is basically self-contained,
    ## because it is essentially a copy of
    ## https://github.com/p4lang/target-syslibs.git. However, in the
    ## context of open-p4studio it is executed via the top-level
    ## CMakeLists.txt and the "install" command was removed. Add it
    ## back here.
    ''
      echo 'install(TARGETS target_sys DESTINATION ''${CMAKE_INSTALL_PREFIX}/lib)' >>CMakeLists.txt
    '';
}
