{ pname, version, src, patches, buildSystem, lib, stdenv, python3,
  cmake, autoconf, automake, libtool, libffi, zlib, sqlite, libedit,
  expat, bf-drivers-src, bf-syslibs }:

## Note: creating a "dev" output for this package with the default
## method creates a dependency cycle between the "out" and "dev"
## outputs.  This should be investigated at some point.
stdenv.mkDerivation ({
  inherit pname version patches;
  src = buildSystem.cmakeFixupSrc {
    inherit src;
    bypass = lib.versionAtLeast version "9.9.0";
    cmakeRules = ''
      include_directories(include)
      include_directories(third-party/tommyds/include)
      include_directories(third-party/xxhash/include)
      include_directories(third-party/judy-1.0.5/src)
      include_directories(third-party/libedit-3.1/src)
    '';
  };

  buildInputs = [ bf-syslibs.dev python3 ]
                ++ lib.optional buildSystem.isCmake
                  ([ cmake autoconf automake libtool ] ++
                   (lib.optional (lib.versionAtLeast version "9.7.0")
                     ## Needed to build the third-party cpython
                     [ libffi libffi.dev zlib sqlite.out ]) ++
                   (lib.optional (lib.versionAtLeast version "9.9.0")
                     ## No longer included as third-party, expat is
                     ## a new dependency
                     [ libedit.dev expat.dev ])
                  );

  enableParallelBuilding = true;
  dontDisableStatic = true;

  outputs = [ "out" "dev" ];

  passthru = {
    ## The version of the embedded Python interpreter as it appears in
    ## the package's include and lib directories. It is used by
    ## bf-drivers to build the parts that need to be linked against
    ## that specific Python version from bf-utils.
    pythonLibPrefix =
      if lib.versionOlder version "9.7.0" then
        "python3.4m"
      else if lib.versionOlder version "9.9.1" then
        "python3.8"
      else
        "python3.10";
  };

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
                if (lib.versionOlder version "9.7.0") then
                  ''
                    cp tmp/src/bf_rt/bf_rt_python/bfrt* ../third-party/bf-python/Lib
                  ''
                else
                  ## Starting with 9.7.0, the third-party/bf-python
                  ## directory no longer exists and neither does the
                  ## CMake logic that installed the bf_rt_python
                  ## artifacts from there. Also see the comment
                  ## further down.
                  ''
                    mkdir ../bf_rt_python
                    cp tmp/src/bf_rt/bf_rt_python/bfrt*  ../bf_rt_python
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
} // lib.optionalAttrs buildSystem.isCmake {
  ## Attributes that did not exist in pre-cmake builds are added here
  ## for cmake builds only to avoid re-building of the autoconf-based
  ## packages. The empty attributes would not change the result of
  ## builds but cause the out paths to change.
  cmakeFlags =
    if (lib.versionOlder version "9.9.0") then
      [ "-DBF-PYTHON=ON" ]
    else
      [ "-DCPYTHON=ON" ];

  preConfigure =
    if (lib.versionOlder version "9.7.0") then ''
      patchShebangs third-party/bf-python
    '' else
      ## Starting with 9.7.0, the install procedure of the
      ## bf_rt_python modules has been removed from
      ## bf-utils.  However, our procedure still requires
      ## those modules to be part of the bf-utils
      ## package. The corresponding CMake rule is also
      ## removed from the bf-drivers package.
      ##
      ## The other two lines set up the compiler flags needed by
      ## third-party/cpython/setup.py to find the header files and
      ## link libraries for libffi, libz and libsqlite3. By default,
      ## it only searches in standard locations and the automatic Nix
      ## magic doesn't work in this case.
      ''
        echo 'install(DIRECTORY ''${CMAKE_CURRENT_SOURCE_DIR}/bf_rt_python/ DESTINATION lib/python3.8)' >>CMakeLists.txt
        NIX_CFLAGS_COMPILE="-lffi -lz -lsqlite3 $NIX_CFLAGS_COMPILE"
        sed -i -e 's!LDFLAGS=\([^ ]*\)!"CPPFLAGS=-I${zlib.dev}/include -I${sqlite.dev}/include" "LDFLAGS=-L${zlib.static}/lib -L${sqlite.out}/lib \1"!' third-party/CMakeLists.txt
      '';

  postInstall = lib.optionalString (lib.versionAtLeast version "9.7.0") ''
    $out/bin/$(basename $out/lib/python*) -m compileall $out/lib/python*/bfrt*
  '';
}
)
