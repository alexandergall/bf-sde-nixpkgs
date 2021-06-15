{ lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: { model }:
    let
      derivation =
        { version, lib, stdenv, thrift, boost, libusb, curl,
          bf-syslibs, bf-drivers, bf-utils }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = patches.default or [];

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb curl bf-syslibs.dev
                          bf-drivers.dev bf-utils ];
          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;

          preConfigure = ''
            mkdir bf-platforms
            tar -C bf-platforms -xf packages/bf-platforms* --strip-components 1
            cd bf-platforms
          '';

          configureFlags =
            (if model then
              [ "--with-model" ]
             else
               [ "--with-tofino" ]) ++
            [ "enable_thrift=yes" ];

          postInstall = ''
            for file in $out/bin/*.sh; do
              substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
            done
          '';
        };
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  accton = {
    model = false;
  };
  model = {
    model = true;
  };
}
