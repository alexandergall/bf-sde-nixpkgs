{ version, lib, callPackage, src, patches, cgoslx, nct6779d,
  asterfusion_version, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      derivation = { stdenv, autoreconfHook, libusb, curl, bf-syslibs,
                     bf-drivers, bf-utils, bf-utils-tofino, i2c-tools }:

        let
          cgos = callPackage asterfusion/cgoslx.nix {
            inherit cgoslx;
          };
        in stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = (patches.default or []) ++ (patches.${baseboard} or []);
          buildInputs = [ autoreconfHook libusb curl bf-syslibs
                          bf-drivers bf-utils i2c-tools cgos ] ++
                          lib.optional (lib.versionAtLeast version "9.9.0") bf-utils-tofino;
          outputs = [ "out" "dev" ];
          passthru = {
            inherit cgos;
            nct6779d = callPackage asterfusion/nct6779d.nix {
              inherit nct6779d;
            };
          };
          configureFlags = [
            "--with-sde-version=${builtins.replaceStrings [ "." ] [ "" ] version}"
          ];
          preConfigure = ''
            cat <<EOF >platforms/asterfusion-bf/include/version.h
            #ifndef VC_VERSION_H
            #define VC_VERSION_H
            #define VERSION_NUMBER "${asterfusion_version}"
            #endif
            EOF
            SDE_VERSION=$(cat ${bf-drivers}/share/VERSION | sed -e 's/\.//g')
            NIX_CFLAGS_COMPILE="-DSDE_VERSION=$SDE_VERSION -DOS_VERSION=10 $NIX_CFLAGS_COMPILE"
          '';
        };
    in callPackage derivation {};

in lib.mapAttrs mkBaseboard {
  asterfusion = {};
}
