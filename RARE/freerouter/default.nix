{ stdenv, fetchFromGitHub, jdk, jre_headless, libpcap, openssl, dpdk, makeWrapper }:

stdenv.mkDerivation rec {
  name = "freerouter-${version}";
  version = "20.9.19";

  src = fetchFromGitHub {
    owner = "mc36";
    repo = "freerouter";
    rev = "0c04126";
    sha256 = "1ccc8q20c4sg55ha9p8r0kv01dxak1xr627mzq01ya0cxcglc27m";
  };

  outputs = [ "out" "native" ];
  buildInputs = [ jdk jre_headless makeWrapper libpcap openssl dpdk ];

  buildPhase = ''
    set -e
    mkdir binTmp
    pushd misc/native
    NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE -isystem ${dpdk}/include/dpdk"
    ./c.sh
    popd
    pushd src
    javac router.java
    popd
  '';

  installPhase = ''
    pushd src

    mkdir -p $out/bin
    mkdir -p $out/share/java

    jar cf $out/share/java/freerouter.jar router.class */*.class
    makeWrapper ${jre_headless}/bin/java $out/bin/freerouter \
      --add-flags "-cp $out/share/java/freerouter.jar router"

    popd

    mkdir -p $native/bin
    cp binTmp/*.bin $native/bin
  '';

}
