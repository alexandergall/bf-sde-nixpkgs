{ pname, version, src, patches, stdenv, python3, thrift, boost, libpcap, p4c,
  bf-syslibs, bf-utils, bf-drivers }:

stdenv.mkDerivation rec {
  inherit pname version src patches;

  buildInputs = [ thrift boost libpcap p4c bf-syslibs.dev bf-utils
                  bf-drivers.dev python3 ];
  outputs = [ "out" "dev" ];
  enableParallelBuilding = true;

  configureFlags = [
    "--with-tofino"
    "--with-libpcap=${libpcap}"
    "enable_thrift=yes"
  ];

  preConfigure = ''
    substituteInPlace third-party/libcrafter/configure --replace withval/include/net/bpf.h withval/include/pcap.h
  '';
  postConfigure = ''
    patchShebangs p4-build
  '';
}
