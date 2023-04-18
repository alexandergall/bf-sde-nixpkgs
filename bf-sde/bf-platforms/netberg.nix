{ version, lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      derivation = { stdenv, cmake, thrift, boost, libusb,
                     curl, bf-syslibs, bf-drivers, bf-utils,
                     bf-utils-tofino, buildSystem }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version;
          src = if (lib.versionAtLeast version "9.9.0")
                then
                  buildSystem.cmakeFixupSrc {
                    inherit src;
                  }
                else
                  src;

          patches = (patches.default or []) ++ (patches.${baseboard} or []);

          buildInputs = [ cmake thrift boost libusb curl bf-syslibs
                          bf-drivers bf-utils ] ++
                        lib.optionals (lib.versionAtLeast version "9.9.0")
                          [ bf-utils-tofino.dev ];
          cmakeFlags = [
            "-DSTANDALONE=ON"
            "-DASIC=ON"
          ];
          preConfigure =
            if (lib.versionOlder version "9.9.0") then ''
              tar xf bf-platforms*
            '' else ''
              rm packages/bf-platforms*.tgz
              cd packages/bf-platforms*
              mv ../../cmake .
              mv CMakeLists.txt CMakeLists.txt.orig
              mv ../../CMakeLists.txt .
              cat CMakeLists.txt.orig >>CMakeLists.txt
            '' + ''
            substituteInPlace platforms/netberg-bf/src/bf_pltfm_chss_mgmt/bf_pltfm_bd_eeprom.c \
              --replace eth0 mgmt0
            substituteInPlace platforms/netberg-bf/src/bf_pltfm_chss_mgmt/bf_pltfm_bd_eeprom.c \
              --replace "grep -i '%s'" "grep -i '%s' 2>&1"
          '';
        };
    in callPackage derivation {};

in lib.mapAttrs mkBaseboard {
  netberg_710 = {
  };
}
