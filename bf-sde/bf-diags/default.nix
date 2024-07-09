{ pname, version, src, patches, buildSystem, lib, stdenv, python311,
  thrift, boost, libpcap, cmake, autoconf, automake, libtool, p4c,
  bf-syslibs, bf-utils, bf-utils-tofino, bf-drivers }:

stdenv.mkDerivation {
  inherit pname version patches;
  src = buildSystem.cmakeFixupSrc {
    inherit src;
    cmakeRules = ''
      find_package(Thrift REQUIRED)
    '';
  };

  buildInputs = [ thrift boost libpcap p4c bf-syslibs.dev bf-utils
                  bf-drivers.dev python311 ]
  ++ (lib.optional buildSystem.isCmake [ cmake autoconf automake libtool ])
  ++ (lib.optional (lib.versionAtLeast version "9.9.0") [ bf-utils-tofino.dev ]);
  outputs = [ "out" "dev" ];
  enableParallelBuilding = true;

  configureFlags = lib.optionals (! buildSystem.isCmake) [
    "--with-tofino"
    "--with-libpcap=${libpcap}"
    "enable_thrift=yes"
  ];
  cmakeFlags = lib.optionals buildSystem.isCmake [
    "-DTOFINO=ON"
    "-DTHRIFT-DRIVER=ON"
    "-DP4C=${p4c}/bin/bf-p4c"
    "-DPDGEN=${bf-drivers}/bin/generate_tofino_pd"
    "-DPDGENCLI=${bf-drivers}/bin/gencli"
    "-DPDSPLIT=${bf-drivers}/bin/split_pd_thrift.py"
  ];

  preConfigure =
    if (! buildSystem.isCmake) then
      ''
        substituteInPlace third-party/libcrafter/configure --replace withval/include/net/bpf.h withval/include/pcap.h
      ''
    else
      ## Satisfy make dependencies
      ''
        touch bf-p4c driver
      '';
  postConfigure = lib.optionalString (lib.versionOlder version "9.6.0") ''
    patchShebangs p4-build
  '';
}
