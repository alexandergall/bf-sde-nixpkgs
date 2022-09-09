{ lib, callPackage, src, patches, version, ... }:

let
  derivation =

    { version, runCommand, stdenv, cmake, bf-syslibs, bf-drivers,
      bf-utils, bf-utils-tofino, i2c-tools, ipmitool, thrift, boost,
      baseboard }:

    let
      src' = runCommand "bf-aps-${version}-bsp.tgz" {} ''
        tar xf ${src} --wildcards "*/packages" --strip-components 2
        mv bf-platforms* $out
      '';

    in stdenv.mkDerivation {
      pname = "bf-platforms-${baseboard}";
      inherit version;
      src = src';
      patches = (patches.default or []) ++ (patches.${baseboard} or []);

      buildInputs = [ cmake bf-drivers.pythonModule bf-syslibs
                      bf-utils.dev bf-utils-tofino.dev bf-drivers
                      i2c-tools thrift boost ];

      cmakeFlags = [
        "-DSTANDALONE:BOOL=ON"
        "-DTHRIFT-DRIVER=ON"
      ];

      preConfigure = ''
        sed -i -e '/CMP0135/d' CMakeLists.txt
        substituteInPlace platforms/bf2556x-1t/src/ipmi/ipmi.c \
          --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
        substituteInPlace platforms/common/src/ipmi.c \
          --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
      '';
    };
in {
  aps_bf2556 = callPackage derivation { baseboard = "aps_bf2556"; };
}
