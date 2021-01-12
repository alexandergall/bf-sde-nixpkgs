{ pname, version, src, stdenv, python3, thrift, boost, libusb, curl_7_52,
  bf-syslibs, bf-drivers, bf-utils }:

stdenv.mkDerivation rec {
  inherit pname version src;

  buildInputs = [ python3 thrift boost libusb curl_7_52 bf-syslibs.dev
                  bf-drivers.dev bf-utils ];
  outputs = [ "out" "dev" ];
  enableParallelBuilding = true;

  preConfigure = ''
    mkdir bf-platforms
    tar -C bf-platforms -xf packages/bf-platforms* --strip-components 1
    cd bf-platforms
  '';

  configureFlags = [
    "--with-tofino"
    "enable_thrift=yes"
  ];

  ## Note: tofino_pci_bringup.sh assumes that the ASIC registers as
  ## device 05:00.0, but this depends on the platform (on the
  ## wedge100bf-32x it is 06:00.0)
  postInstall = ''
    for file in $out/bin/*.sh; do
      substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
    done
  '';
}
