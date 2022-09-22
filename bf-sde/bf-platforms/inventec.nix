{ lib, callPackage, version, src, patches, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      versionOlder9_7 = lib.versionOlder version "9.7.0";
      derivation =
        { version, stdenv, thrift, boost, libusb, curl,
          bf-syslibs, bf-drivers, bf-utils, bf-utils-tofino,
          cmake }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = patches.default or [];

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl bf-syslibs.dev bf-drivers.dev bf-utils
                          ] ++ lib.optional (! versionOlder9_7) cmake
                          ++ lib.optional (lib.versionAtLeast version
                          "9.9.0") bf-utils-tofino;
          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;
          ## The platform libraries have unresolved references on
          ## (unused) functions, which is incompatible with the
          ## default immediate bindings used by mkDerivation.
          hardeningDisable = lib.optional (! versionOlder9_7) "bindnow";

          unpackPhase = lib.optionalString (! versionOlder9_7) ''
            mkdir inventec
            cd inventec
            tar -xf ${src}
          '';
          preConfigure = if versionOlder9_7 then ''
            cd bf-platforms
          '' else
            lib.optionalString (lib.versionAtLeast version "9.8.0") ''
              sed -i -e 's/THRIFT_VERSION_STRING/THRIFT_VERSION/' platforms/accton-bf/thrift/CMakeLists.txt
            '' + lib.optionalString (lib.versionAtLeast version "9.9.0") ''
              substituteInPlace CMakeLists.txt \
                --replace bfsys target_sys
              for f in $(find . -type f); do
                sed -i -e 's/#include <bfsys/#include <target-sys/;s/#include <bfutils/#include <target-utils/' $f
              done
            '' + ''
              sed -i -e '/bf_fpga/d' CMakeLists.txt
            '';

          configureFlags = lib.optionals versionOlder9_7 [
            "--with-tofino"
            "enable_thrift=yes"
          ];

          CFLAGS = lib.optionals versionOlder9_7 [
            "-Wno-error=unused-result"
            "-Wno-error=sizeof-pointer-memaccess"
          ];
          cmakeFlags = lib.optionals (! versionOlder9_7) [
            "-DSTANDALONE=ON"
            "-DASIC=ON"
            "-DINVENTEC=ON"
          ];
        };

    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  inventec = {};
}
