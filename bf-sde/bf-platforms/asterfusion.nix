{ version, lib, callPackage, src, patches, cgoslx, nct6779d,
  asterfusion_version, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      derivation = { stdenv, cmake, makeWrapper, libusb, curl, target-syslibs,
                     bf-drivers, target-utils, bf-utils, i2c-tools, coreutils,
                     kmod, gnugrep, gawk, thrift, boost, python3, which }:

        let
          cgos = callPackage asterfusion/cgoslx.nix {
            inherit cgoslx;
          };
        in stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = (patches.default or []) ++ (patches.${baseboard} or []);
          buildInputs = [ cmake makeWrapper libusb curl
                          target-syslibs thrift boost bf-drivers target-utils
                          bf-utils i2c-tools cgos python3 which ];
          outputs = [ "out" "dev" ];
          passthru = {
            inherit cgos;
            nct6779d = callPackage asterfusion/nct6779d.nix {
              inherit nct6779d;
            };
          };
          CFLAGS = lib.optionals (lib.versionAtLeast stdenv.cc.version "12.0") [
            "-Wno-error=address"
            "-Wno-error=stringop-overflow"
            "-Wno-error=stringop-truncation"
            "-Wno-error=maybe-uninitialized"
          ];
          cmakeFlags = [
            "-DOS_VERSION=12"
            "-DSDE_VERSION=${builtins.replaceStrings [ "." ] [ "" ] version}"
          ];
          preConfigure = ''
            cat <<EOF >platforms/asterfusion-bf/include/version.h
            #ifndef VC_VERSION_H
            #define VC_VERSION_H
            #define VERSION_NUMBER "${asterfusion_version}"
            #endif
            EOF
          '';
          postInstall = ''
            wrapProgram $out/bin/xt-cfgen.sh \
              --set PATH $out/bin:"${lib.strings.makeBinPath [ coreutils kmod gnugrep gawk i2c-tools ]}"
          '';
        };
    in callPackage derivation {};

in lib.mapAttrs mkBaseboard {
  asterfusion = {};
}
