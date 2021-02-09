{ pname, version, src, patches, stdenv, python, thrift, openssl, boost,
  pkg-config, grpc, protobuf, zlib, bf-syslibs, bf-utils }:

assert stdenv.isx86_64 || stdenv.isi686;

let
  bf-drivers = stdenv.mkDerivation {
    inherit pname version src;

    passthru = {
      sitePackagesPath = "${bf-drivers}/lib/${python.libPrefix}/site-packages";
    };

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
      path=$out/lib/${python.libPrefix}/site-packages
      rm $path/tofino_pd_api/tenjin.*
    '' +

    ## Turn google/rpc into a "google" namespace package
    ## by adding a .pth file, creating a link to google
    ## in the top-level site-packages directory and removing
    ## __init__.py.  To make this work, all portions of the
    ## name space have to be added with site.addsite(), for
    ## example by adding bf-drivers and the protobuf Python
    ## package to a Python environment (just adding them to
    ## PYTHONPATH is not sufficient).
    ''
      cp ${./rpc-nspkg.pth} $path/rpc-nspkg.pth
      ln -sr $path/tofino/google $path
      rm -f $path/tofino/google/__init__.py*
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
