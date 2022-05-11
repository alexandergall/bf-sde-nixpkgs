{ lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: { model }:
    let
      derivation =
        { version, buildSystem, lib, stdenv, thrift, boost, libusb,
          curl, bf-syslibs, bf-drivers, bf-utils, cmake, runCommand }:

        stdenv.mkDerivation ({
          pname = "bf-platforms-${baseboard}";
          ## Note: src is the actual reference BSP archive, see
          ## default.nix
          inherit version src;
          patches = patches.default or [];

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl bf-syslibs.dev bf-drivers.dev bf-utils
                          ] ++ lib.optional buildSystem.isCmake [
                          cmake ];

          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;

          configureFlags = lib.optional (! buildSystem.isCmake)
            (if model then
              [ "--with-model" ]
             else
               [ "--with-tofino" ]) ++
            [ "enable_thrift=yes" ];

          postInstall = ''
            for file in $out/bin/*.sh; do
              substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
            done
          '' + lib.optionalString buildSystem.isCmake ''
            python -m compileall $out/lib/${bf-drivers.pythonModule.libPrefix}/site-packages
          '';
        } // lib.optionalAttrs buildSystem.isCmake {
          cmakeFlags =
            (if model then
              [ "-DASIC=OFF" ]
             else
               [ "-DASIC=ON" ]) ++
            [ "-DSTANDALONE=ON" ];
        });
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  accton = {
    model = false;
  };
  model = {
    model = true;
  };
}
