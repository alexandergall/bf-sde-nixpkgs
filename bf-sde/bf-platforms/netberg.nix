{ version, lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      derivation = { stdenv, cmake, thrift, boost, libusb,
                     curl, bf-syslibs, bf-drivers, bf-utils }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = (patches.default or []) ++ (patches.${baseboard} or []);

          buildInputs = [ cmake thrift boost libusb curl bf-syslibs
                          bf-drivers bf-utils ];
          cmakeFlags = [
            "-DSTANDALONE=ON"
            "-DASIC=ON"
          ];
          preConfigure = ''
            tar xf bf-platforms*
           substituteInPlace platforms/netberg-bf/src/bf_pltfm_chss_mgmt/bf_pltfm_bd_eeprom.c \
             --replace eth0 mgmt0
           '';
        };
    in callPackage derivation {};

in lib.mapAttrs mkBaseboard {
  netberg_710 = {
  };
}
