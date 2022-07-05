{ lib, callPackage, src, patches, reference, version, ... }:

if (lib.versionOlder version "9.9.0") then
  import ./aps-sal.nix {
    inherit lib callPackage src patches reference version;
  }
else let
  mkBaseboard = baseboard: { pltfmCmakeFlags }:
    let
      derivation = { version, runCommand, stdenv, cmake,
                     bf-syslibs, bf-drivers, bf-utils,
                     bf-utils-tofino, i2c-tools, ipmitool }:

        let
          src' = runCommand "bf-aps-${version}-bsp.tgz" {} ''
            tar xf ${src} --wildcards "*/packages" --strip-components 2
            mv bf-platforms* $out
          '';
          i2c-tools' = i2c-tools.overrideAttrs (_: {
            postInstall = "";
          });

        in stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version;
          src = src';
          patches = (patches.default or []) ++ (patches.${baseboard} or []);

          buildInputs = [ cmake bf-drivers.pythonModule bf-syslibs
                          bf-utils.dev bf-utils-tofino.dev bf-drivers i2c-tools' ];

          cmakeFlags = [
            "-DSTANDALONE=ON"
            "-DTHRIFT_ENABLED=OFF"
          ] ++ pltfmCmakeFlags;

          preConfigure = ''
            substituteInPlace platforms/bf2556x-1t/src/ipmi/ipmi.c \
              --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
          '';
        };
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  aps_bf2556 = {
    pltfmCmakeFlags = [ "-DPLATFORM=BF2556X-1T" ];
  };
}
