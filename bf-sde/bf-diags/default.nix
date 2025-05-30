{ pname, version, src, patches, buildSupport, lib, stdenv, python3,
  thrift, boost, libpcap, cmake, autoconf, automake, libtool, p4c,
  target-syslibs, target-utils, bf-utils, bf-drivers }:

stdenv.mkDerivation {
  inherit pname version patches;
  src = buildSupport.fixupSrc {
    inherit src;
    cmakeRules = ''
      find_package(Thrift REQUIRED)
    '';
  };

  buildInputs = [ cmake autoconf automake libtool thrift boost libpcap
                  p4c target-syslibs.dev target-utils bf-drivers.dev python3
                  bf-utils ];
  outputs = [ "out" "dev" ];
  enableParallelBuilding = true;

  cmakeFlags = [
    "-DTOFINO=ON"
    "-DTHRIFT-DRIVER=ON"
    "-DP4C=${p4c}/bin/bf-p4c"
    "-DPDGEN=${bf-drivers}/bin/generate_tofino_pd"
    "-DPDGENCLI=${bf-drivers}/bin/gencli"
    "-DPDSPLIT=${bf-drivers}/bin/split_pd_thrift.py"
  ];

  preConfigure =
    ## bf-diags is not compatible with C++17
    ''
      substituteInPlace CMakeLists.txt \
        --replace-fail "CMAKE_CXX_STANDARD 17" "CMAKE_CXX_STANDARD 14"
    '' +
    ## Satisfy make dependencies
    ''
      touch bf-p4c driver
    '';
  postConfigure =
    ## third-party/libcrafter expects the file to be named
    ## "config.h".
    ''
     ln -s p4studio_config.h config.h
    '';
}
