{ pname, version, src, patches, stdenv, python, thrift, openssl, boost,
  pkg-config, grpc, protobuf, zlib, bf-syslibs, bf-utils }:

assert stdenv.isx86_64 || stdenv.isi686;

let
  bf-drivers = stdenv.mkDerivation {
    inherit pname version src;

    propagatedBuildInputs = with python.pkgs; [ grpcio  ];
    buildInputs = [ thrift openssl boost pkg-config grpc protobuf zlib
                    bf-syslibs.dev bf-utils python.pkgs.wrapPython ];
    outputs = [ "out" "dev" ];
    enableParallelBuilding = true;

    patches = patches ++ [ ./bf_switchd_model.patch ];

    configureFlags = [
      "enable_thrift=yes"
      "enable_grpc=yes"
      "enable_bfrt=yes"
      "enable_p4rt=no"
      "enable_pi=no"
      "--without-kdrv"
    ];

    buildFlags = [
      "CFLAGS+=-I${bf-utils}/include/python3.4m"
    ];

    ## Install the precompiled avago library and make it available to
    ## the builder.  Also disable building of bfrt examples.
    preBuild =
      let
        arch = if stdenv.isx86_64
          then
            "x86_64"
          else
            "i686";
      in ''
        mkdir -p $out/lib
        cp libavago.${arch}.a $out/lib/libavago.a
        cp libavago.${arch}.so $out/lib/libavago.so
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
      rm $sitePath/tofino_pd_api/tenjin.*
    '' +

    ## Link the directories in site-packages/tofino and
    ## site-packages/tofino_pd_api to site-packages. This allows
    ## importing those modules without having to add the tofino and
    ## tofino_pd_api directories to the search path. This should be
    ## fine as long as it doesn't create conflicts, which is currently
    ## not the case.
    ##
    ## Also, turn google/rpc into a "google" namespace package
    ## by adding a .pth file, creating a link to google
    ## in the top-level siteq-packages directory and removing
    ## __init__.py.  To make this work, all portions of the
    ## name space have to be added with site.addsite(), for
    ## example by adding bf-drivers and the protobuf Python
    ## package to a Python environment (just adding them to
    ## PYTHONPATH is not sufficient).

    ''
      for obj in $sitePath/tofino/* $sitePath/tofino_pd_api/*; do
        ln -sr $obj $sitePath
      done
      cp ${./rpc-nspkg.pth} $sitePath/rpc-nspkg.pth
      rm -f $sitePath/tofino/google/__init__.py*
    '';

    pythonPath = with python.pkgs; [ tenjin six ];
    postFixup = ''
      wrapPythonPrograms
    '';
  };

## This turns the derivation into a Python Module,
## i.e. $out/lib/python*/site-packages will be included in all of the
## Nix Python wrapper magic
in python.pkgs.toPythonModule bf-drivers
