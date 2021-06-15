{ lib, callPackage, src, patches, reference }:

let
  ## This derivation uses the reference BSP as source and merges the
  ## APS BSPs into it.
  mkBaseboard = baseboard: { diff, zipPattern, CFLAGS }:
    let
      derivation =
        { runCommand, version, unzip, stdenv, thrift, boost, libusb,
          curl, bf-syslibs, bf-drivers, bf-utils, autoconf,
          automake115x }:

        let
          ## This is the full SAL package. It contains the zip files of the
          ## BSPs in the bsp directory.
          ## TBD: build the components that control the gear box.
          src' = runCommand "aps-unpack-bsp" {} ''
            mkdir $out
            cd $out
            ${unzip}/bin/unzip ${src}
          '';

        in stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version CFLAGS;
          inherit (reference) src;

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl unzip bf-syslibs.dev bf-drivers.dev
                          bf-utils autoconf automake115x ];
          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;

          ## Merge the APS BSP with the reference BSP
          preConfigure = ''
            mkdir bf-platforms
            tar -C bf-platforms -xf packages/bf-platforms* --strip-components 1
            cd bf-platforms
            unzip ${src'}/bsp/${zipPattern}
            patch -p1 <${diff}
            for patch in ${builtins.concatStringsSep " " (patches.default or [])}; do
              patch -p1 <$patch
            done
          '';

          configureFlags = [
            "--with-tofino"
            "--with-tof-brgup-plat"
            "enable_thrift=yes"
          ];

          postInstall = ''
            for file in $out/bin/*.sh; do
              substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
            done
          '';
        };
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  aps_bf2556 = {
    diff = "bf2556x_1t.diff";
    zipPattern = "*BF2556*.zip";
    CFLAGS = [
      "-Wno-error=unused-result"
    ];
  };
  aps_bf6064 = {
    diff = "bf6064x_t.diff";
    zipPattern = "*BF6064*.zip";
    CFLAGS = [
      "-Wno-error=maybe-uninitialized"
      "-Wno-error=sizeof-pointer-memaccess"
    ];
  };
}
