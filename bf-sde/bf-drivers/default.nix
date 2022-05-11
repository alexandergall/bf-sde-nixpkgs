{ pname, version, src, patches, buildSystem, stdenv, python, thrift,
  openssl, boost, pkg-config, grpc, protobuf, zlib, bf-syslibs,
  bf-utils, lib, autoreconfHook, cmake, libedit,

## The runtime version of the package doesn't include the gencli and
## generate_tofino_pd components.  They are not used at runtime but,
## more importantly, they are not allowed to be distributed to third
## parties by Intel.
  runtime ? false }:

assert stdenv.isx86_64 || stdenv.isi686;

let

  ## This is a copy of toPythonModule from
  ## pkgs/top-level/python-packages.nix. The problem with the original
  ## (i.e. python.pkgs.toPyhtonModule) is that it uses the
  ## non-overriden python, not the modified one from overlay.nix.
  ## However, we use python from bf-driver's passthru to build python
  ## stuff that depends on bf-drivers and need to see the overrides
  ## there. Hence this copy that *does* use the overridden python.
  toPythonModule = drv:
    drv.overrideAttrs( oldAttrs: {
      passthru = (oldAttrs.passthru or {}) // {
        pythonModule = python;
        pythonPath = [ ];
        requiredPythonModules = python.pkgs.requiredPythonModules drv.propagatedBuildInputs;
      };
    });
  ## The location of C header files for the Python version that comes
  ## embedded in bf-utils to provide the bfrt_python shell in
  ## bf_switchd. Some bf_rt components in bf-drivers need to be
  ## compiled with those headers.
  bfUtilsPythonInclude = "${bf-utils.dev}/include/${bf-utils.pythonLibPrefix}";
  bf-drivers = stdenv.mkDerivation ({
    pname = pname + lib.optionalString runtime "-runtime";
    inherit version patches;
    src = buildSystem.cmakeFixupSrc {
      inherit src;
      cmakeRules = ''
        find_package(Thrift REQUIRED)
        include_directories(include)
        include_directories(.)
        set(PYTHON_SITE lib/${python.libPrefix}/site-packages)
        find_library(BF_PYTHON_LIBRARY NAMES ${bf-utils.pythonLibPrefix} lib${bf-utils.pythonLibPrefix})
      '' + lib.optionalString (lib.versionAtLeast version "9.7.0") ''
        set(PYTHON_EXECUTABLE python3)
      '';
      ## Include the path for Python.h and add explicit linking to
      ## libedit.  libedit is included as third-party component in
      ## bf-utils. The standard monolithic build of the SDE links
      ## bf-drivers to libedit of the source tree inside bf-utils.
      ## Our modular build can't do that (and libedit is not in the
      ## output path of bf-utils), so we add the standard libedit to
      ## the dependencies.
      postCmakeRules = ''
        target_include_directories(bfshell_plugin_debug_o PUBLIC ${bfUtilsPythonInclude})
        target_include_directories(bfshell_plugin_bf_rt_o PUBLIC ${bfUtilsPythonInclude})
        cmake_policy(SET CMP0079 NEW)
        target_link_libraries(bf_switchd edit)
      '';
    };

    propagatedBuildInputs = with python.pkgs; [ grpcio ];
    buildInputs = [ thrift openssl boost pkg-config grpc protobuf zlib
                    bf-syslibs.dev bf-utils bf-utils.dev python.pkgs.wrapPython ]
                  ++ lib.optional (runtime && ! buildSystem.isCmake) autoreconfHook
                  ++ lib.optional buildSystem.isCmake [ cmake libedit python ];
    outputs = [ "out" ] ++ lib.optional (! runtime) "dev";
    enableParallelBuilding = true;

    configureFlags = lib.optional (! buildSystem.isCmake) [
      "enable_thrift=yes"
      "enable_grpc=yes"
      "enable_bfrt=yes"
      "enable_p4rt=no"
      "enable_pi=no"
      "--without-kdrv"
    ];

    buildFlags = lib.optional (! buildSystem.isCmake) [
      "CFLAGS+=-I${bfUtilsPythonInclude}"
    ];

    preConfigure =
      if (! buildSystem.isCmake) then
        ## Intel prohibits the inclusion of pd_api_gen in the runtime
        ## environment.
        lib.optionalString runtime ''
          substituteInPlace Makefile.am --replace "SUBDIRS = third-party include src pd_api_gen doc" "SUBDIRS = third-party include src doc"
        ''
      else
        ## Override the location of libpython provided by
        ## bf-utils.
        ''
          for dir in src/bf_rt src/lld; do
              echo -e '\nset_property(TARGET bfpythonlib PROPERTY IMPORTED_LOCATION ''${BF_PYTHON_LIBRARY})' >>$dir/CMakeLists.txt
          done
        '' +
        ## Disable installation of bf_rt_python files, see the comment
        ## in ../bf-utils/default.nix for details
        ''
          sed -i -e 's/^.*bf_rt_python.*$//' src/bf_rt/CMakeLists.txt
        '' +
        ## Disable bfrt_examples
        ''
          sed -i -e 's/^.*bfrt_examples.*//' bf_switchd/CMakeLists.txt
        '' +
        ## Don't install module load/unload scripts, they are part of the kernel
        ## module packages
        ''
          sed -i -e 's/^.*mod_.*load.*$//' CMakeLists.txt
        '' + lib.optionalString runtime
          ## See above
          ''
            sed -i -e 's/^.*pd_api_gen.*$//' CMakeLists.txt
          '';

    ## Non-cmake builds: install the precompiled avago library and
    ## make it available to the builder.  Also disable building of
    ## bfrt examples.
    preBuild =
      let
        arch = if stdenv.isx86_64
          then
            lib.optionalString (lib.versionOlder version "9.6.0") ".x86_64"
          else
            ".i686";
      in lib.optionalString (! buildSystem.isCmake) ''
        mkdir -p $out/lib
        cp libavago${arch}.a $out/lib/libavago.a
        cp libavago${arch}.so $out/lib/libavago.so
        ln -sr $out/lib/libavago.so $out/lib/libavago.so.0
        ln -sr $out/lib/libavago.so $out/lib/libavago.so.0.0.0
        NIX_LDFLAGS="$NIX_LDFLAGS -L$out/lib"

        substituteInPlace bf_switchd/Makefile \
          --replace "DIST_SUBDIRS = . bfrt_examples" "DIST_SUBDIRS = ." \
          --replace "am__append_1 = bfrt_examples" "am__append_1 ="
      '';

    ## Remove the included tenjin module. For some reason it causes
    ## "NameError: global name 'six' is not defined"
    ## when generate_tofino_pd is run.
    postInstall = ''
      sitePath=$out/lib/${python.libPrefix}/site-packages
    '' + lib.optionalString (! runtime) ''
      rm $sitePath/tofino_pd_api/tenjin.*
    '' +

    ## Work around a long-standing issue with implicit relative
    ## imports of python modules in code generated by protoc when
    ## using Python3, see
    ## https://github.com/protocolbuffers/protobuf/issues/1491.
    ##
    ## In our case, bfruntime_pb2_grpc.py contains the statement
    ##
    ## import bfruntime_pb2 as bfruntime__pb2
    ##
    ## where bfruntime_pb2 is located in the same directory. This
    ## fails with Python3, which requires
    ##
    ## from . import bfruntime_pb2 as bfruntime__pb2
    lib.optionalString python.isPy3 ''
      sed -i -e 's/import bfruntime_pb2/from . import bfruntime_pb2/' $sitePath/tofino/bfrt_grpc/bfruntime_pb2_grpc.py
    '' +

    ## Link the directories in site-packages/tofino and
    ## site-packages/tofino_pd_api to site-packages. This allows
    ## importing those modules without having to add the tofino and
    ## tofino_pd_api directories to the search path. This should be
    ## fine as long as it doesn't create conflicts, which is currently
    ## not the case.
    ##
    ## Also, turn google/rpc into a "google" namespace package by
    ## adding a .pth file, creating a link to google in the top-level
    ## site-packages directory and removing __init__.py.  To make this
    ## work, all portions of the name space have to be added with
    ## site.addsite(), for example by adding bf-drivers and the
    ## protobuf Python package to a Python environment (just adding
    ## them to PYTHONPATH is not sufficient).
    ''
      for obj in $sitePath/tofino/* ${lib.optionalString (! runtime) "$sitePath/tofino_pd_api/*"}; do
        ln -sr $obj $sitePath
      done
      cp ${./rpc-nspkg.pth} $sitePath/rpc-nspkg.pth
      rm -f $sitePath/tofino/google/__init__.py*
    '' +

    lib.optionalString buildSystem.isCmake ''
      python -m compileall $sitePath
    '' +

    ## The runtime version doesn't have a "dev" output.
    lib.optionalString runtime ''
      rm -rf $out/include
    '' +

    ## This utility was part of the ptf-utils package up to 9.7.0
    lib.optionalString (lib.versionAtLeast version "9.8.0") ''
      chmod a+x $out/lib/${python.libPrefix}/site-packages/p4testutils/bf_switchd_dev_status.py
    '';

    ## Declare the set of modules to be used by wrapPythonPrograms.
    pythonPath = with python.pkgs; [ tenjin six ];
    postFixup = lib.optionalString (! runtime && lib.versionAtLeast version "9.6.0") ''
      [ -f $out/bin/split_pd_thrift.py ] && chmod a+x $out/bin/split_pd_thrift.py
    '' + ''
      wrapPythonPrograms
    '' + lib.optionalString (lib.versionAtLeast version "9.8.0") ''
      wrapPythonProgramsIn $out/lib/${python.libPrefix}/site-packages/p4testutils "$pythonPath"
    '';
  } // lib.optionalAttrs buildSystem.isCmake {
    cmakeFlags = [
      "-DTHRIFT-DRIVER=ON"
      "-DGRPC=ON"
      "-DBFRT=ON"
      "-DPI=OFF"
      "-DP4RT=OFF"
      "-DBF-PYTHON=ON"
      ## Indirectly disable build of kdrv
      "-DASIC=OFF"
    ];
  });

## This turns the derivation into a Python Module,
## i.e. $out/lib/python*/site-packages will be included in all of the
## Nix Python wrapper magic
in toPythonModule bf-drivers
