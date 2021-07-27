{ lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: { model }:
    let
      derivation =
        { version, buildSystem, lib, stdenv, thrift, boost, libusb,
          curl, bf-syslibs, bf-drivers, bf-utils, cmake }:

        stdenv.mkDerivation ({
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = patches.default or [];

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl bf-syslibs.dev bf-drivers.dev bf-utils
                          ] ++ lib.optional buildSystem.isCmake [
                          cmake ];

          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;

          preConfigure = buildSystem.preConfigure {
            package = "bf-platforms";
            cmakeRules = ''
              find_package(Thrift REQUIRED)
              add_subdirectory(''${BF_PKG_DIR}/bf-platforms)
            '';
            preCmds = ''
              tar -xf packages/bf-platforms* --strip-components 1
            '';
            alternativeCmds = ''
              mkdir bf-platforms
              tar -C bf-platforms -xf packages/bf-platforms* --strip-components 1
              cd bf-platforms
            '';
          };

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
            [ "-DTHRIFT-DRIVER=ON" ];
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
