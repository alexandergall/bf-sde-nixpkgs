{ lib, callPackage, version, src, patches, ... }:

let
  mkBaseboard = baseboard: {}:
    let
      versionOlder9_7 = lib.versionOlder version "9.7.0";
      derivation =
        { version, stdenv, thrift, boost, libusb, curl,
          bf-syslibs, bf-drivers, bf-utils, cmake }:

        stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version src;
          patches = patches.default or [];

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl bf-syslibs.dev bf-drivers.dev bf-utils
                        ] ++ lib.optional (! versionOlder9_7) cmake;
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
          '' else ''
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
