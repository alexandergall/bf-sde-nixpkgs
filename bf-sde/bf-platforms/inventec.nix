{ lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      derivation =
        { version, stdenv, thrift, boost, libusb, curl,
          bf-syslibs, bf-drivers, bf-utils }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = patches.default or [];

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl bf-syslibs.dev bf-drivers.dev bf-utils
                          ];
          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;

          preConfigure = ''
            cd bf-platforms
          '';

          configureFlags = [
            "--with-tofino"
            "enable_thrift=yes"
          ];

          CFLAGS = [
            "-Wno-error=unused-result"
            "-Wno-error=sizeof-pointer-memaccess"
          ];
        };
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  inventec = {};
}
