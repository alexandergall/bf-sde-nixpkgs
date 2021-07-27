{ pname, version, src, patches, buildSystem, lib, stdenv, python3,
  cmake, autoconf, automake, libtool, bf-drivers-src, bf-syslibs }:

## Note: creating a "dev" output for this package with the default
## method creates a dependency cycle between the "out" and "dev"
## outputs.  This should be investigated at some point.
stdenv.mkDerivation ({
  inherit pname version src patches;

  buildInputs = [ bf-syslibs.dev python3 ]
                ++ lib.optional buildSystem.isCmake [ cmake autoconf automake libtool ];

  enableParallelBuilding = true;
  dontDisableStatic = true;

  outputs = [ "out" "dev" ];

  ## bf-python requires a bit of trickery starting with 9.3.0.
  ## bf-utils contains a full Python interpreter with a customized
  ## IPython module. This is called from bf_switchd when "bfrt_python"
  ## is invoked.  The entry-point is the start_bfrt() function of
  ## bfrtcli.py. So far, so good.
  ##
  ## The problem is that bfrtcli.py along with 4 other modules is
  ## included in this package as well as in the bf-drivers package,
  ## but the versions differ. From the way the modules are installed
  ## by p4studio, the modules from bf-drivers overwrite those of
  ## bf-utils when installed into the common SDE_INSTALL tree.  This
  ## "trick" doesn't work here.  So, what we do is get those files
  ## from the bf-drivers source before we build.
  preBuild =
    (if (lib.versionAtLeast version "9.3.0")
      then
        ''
          mkdir tmp
          tar -C tmp -xf ${bf-drivers-src} --strip-component 1
        '' + (if buildSystem.isCmake
              then
                ''
                  cp tmp/src/bf_rt/bf_rt_python/bfrt* ../third-party/bf-python/Lib
                ''
              else
                ''
                  cp tmp/src/bf_rt/bf_rt_python/bfrt* third-party/bf-python/Lib
                '')
     else
       "") +
    ''
      patchShebangs third-party
    '';

  ## Hacks to get rid of issues when creating the "dev" output.  They
  ## should be harmless because they would only affect someone wanting
  ## to build Python stuff for the Interpreter embedded in the
  ## package, which nobody should ever want to do (the embedded
  ## interpreter is used to provide a modified version of IPython used
  ## by bfrt_python inside bfshell).
  preFixup = lib.optionalString (! buildSystem.isCmake) ''
    mv $out/include/python*/pyconfig.h $dev/include/python*/
    rmdir $out/include/python*

    for file in $out/lib/python*/_sysconfigdata.py $out/lib/python*/config*/Makefile $out/lib/python*/__pycache__/_sysconfigdata*; do
      substituteInPlace $file --replace $dev /removed-bf-utils-dev-reference
    done
  '';
} // lib.optionalAttrs (buildSystem.isCmake) {
  preConfigure = buildSystem.preConfigure {
    package = "bf-utils";
    cmakeRules = ''
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/tommyds/include)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/xxhash/include)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/cjson/include)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/judy-1.0.5/src)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/bigcode/include)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/klish)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/libedit-3.1/src)
      include_directories(''${BF_PKG_DIR}/bf-utils/third-party/bf-python/Include)
      include_directories(''${CMAKE_CURRENT_BINARY_DIR}/''${BF_PKG_DIR}/bf-utils/third-party/libpython3.4m/src/libpython3.4m-build/)
      include_directories(''${BF_PKG_DIR}/bf-utils/include)
      add_subdirectory(''${BF_PKG_DIR}/bf-utils)
    '';
    postCmds = ''
      patchShebangs third-party/bf-python
    '';
  };
})
