{ version, lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      derivation = { stdenv, cmake, buildSystem, thrift, boost,
                     libusb, curl, bf-syslibs, bf-drivers, bf-utils }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = (patches.default or []) ++ (patches.${baseboard} or []);

          buildInputs = [ cmake thrift boost libusb curl bf-syslibs
                          bf-drivers bf-utils ];
          cmakeFlags = [
            "-DSTANDALONE=ON"
          ];
          preConfigure = ''
            tar xf bf-platforms*
          '';
        };
    in callPackage derivation {};

in lib.mapAttrs mkBaseboard {
  netberg_7xx = {
  };
}
