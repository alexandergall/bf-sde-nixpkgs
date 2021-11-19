{ pname, version, src, patches, buildSystem, lib, stdenv, python3,
  thrift, boost, libpcap, cmake, autoconf, automake, libtool, p4c,
  bf-syslibs, bf-utils, bf-drivers }:

stdenv.mkDerivation ({
  inherit pname version src patches;

  buildInputs = [ thrift boost libpcap p4c bf-syslibs.dev bf-utils
                  bf-drivers.dev python3 ]
  ++ (lib.optional buildSystem.isCmake [ cmake autoconf automake libtool ]);
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
  postConfigure = lib.optionalString (lib.versionOlder version "9.6.0") ''
    patchShebangs p4-build
  '';
} // lib.optionalAttrs (buildSystem.isCmake) {
  preConfigure = buildSystem.preConfigure {
    package = "bf-diags";
    cmakeRules = ''
      set(TOFINO ON)
      set(THRIFT-DRIVER ON)
      set(P4C ${p4c}/bin/bf-p4c)
      set(PDGEN ${bf-drivers}/bin/generate_tofino_pd)
      set(PDGENCLI ${bf-drivers}/bin/gencli)
      set(PDSPLIT ${bf-drivers}/bin/split_pd_thrift.py)
      if (THRIFT-DRIVER OR THRIFT-SWITCH OR THRIFT-DIAGS)
        find_package(Thrift REQUIRED)
      endif()
      add_subdirectory(''${BF_PKG_DIR}/bf-diags)
    '';
    postCmds =
      ## Satisfy make dependencies
      ''
        touch bf-p4c driver
      '';
  };
})
