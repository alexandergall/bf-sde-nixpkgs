{ pname, version, src, patches, system, stdenv, python2, thrift, openssl, boost,
  pkg-config, grpc, protobuf, zlib, bf-syslibs, bf-utils }:

assert stdenv.isx86_64 || stdenv.isi686;

let
  ## grpcio is a runtime dependency for using the brft-python
  ## interface.  It also creates the "google" namespace package which
  ## bfrt-python is a part of via
  ## lib/python2.7/site-packages/tofino/google.  The setuptools
  ## package is needed to make that namespace package work with python
  ## applications that have bf-drivers as a dependency. tenjin overrides
  ## the broken tenjin included in third-party.
  python2Env = python2.withPackages (ps: with ps;
    [ grpcio tenjin setuptools ]);
  arch = if stdenv.isx86_64
    then
      "x86_64"
    else if stdenv.isi686
      then
        "i686"
      else
        throw "Unsupported architecture";
in stdenv.mkDerivation {
  inherit pname version src;

  propagatedBuildInputs = [ python2Env ];
  buildInputs = [ thrift openssl boost pkg-config grpc protobuf zlib
                  bf-syslibs.dev bf-utils ];
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
  preBuild = ''
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
}
