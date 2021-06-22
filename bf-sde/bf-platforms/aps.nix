{ lib, callPackage, src, patches, reference }:

let
  ## This derivation uses the reference BSP as source and merges the
  ## APS BSP into it.
  mkBaseboard = baseboard: { diff, zipPattern, CFLAGS }:
    let
      derivation =
        { runCommand, version, unzip, stdenv, thrift, boost, libusb,
          curl, coreutils, bf-syslibs, bf-drivers, bf-utils, autoconf,
          automake115x, autoPatchelfHook, icu60, i2c-tools, gawk, xz,
          utillinux, mount, umount, cpio, gnused }:

        let
          ## This is the full "APS One Touch" package. It contains the
          ## zip files of the BSPs in the bsp directory.
          src' = runCommand "aps-unpack-bsp" {} ''
            mkdir $out
            cd $out
            ${unzip}/bin/unzip ${src}
          '';
          python = bf-drivers.pythonModule;

        in stdenv.mkDerivation {
          pname = "bf-platforms-${baseboard}";
          inherit version CFLAGS;
          inherit (reference) src;

          buildInputs = [ python thrift boost libusb curl unzip bf-syslibs.dev
                          bf-drivers.dev bf-utils autoconf automake115x
                          autoPatchelfHook icu60 ];
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

            substituteInPlace platforms/apsn/src/bf_pltfm_chss_mgmt/bf_pltfm_bd_eeprom.c \
              --replace onie-syseeprom $out/bin/onie-syseeprom

          '';

          configureFlags = [
            "--with-tofino"
            "--with-tof-brgup-plat"
            "enable_thrift=yes"
          ];

          postInstall = ''

            ## The APS boxes actually don't have a CP2112 (at least
            ## not the BF2556X_1T). Maybe we should just remove the
            ## scripts that reference the cp2112 utility.
            for file in $out/bin/*.sh; do
              substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
            done

            ## Install the pre-built SAL
            pushd ${src'}/APS-One-touch*/release/sal*
            cp build/salRefApp $out/bin
            chmod a+x $out/bin/salRefApp
            cp sal_tp_install/lib/*.so* $out/lib
            mkdir $out/config
            ## Configuration Files used by the SAL
            cp ${aps/sal.ini} -r $out/config/sal.ini
            cp ${aps/logger.ini} -r $out/config/logger.ini

            ## Generate the gRPC python bindings for the SAL
            ${python.pkgs.grpcio-tools}/lib/${python.libPrefix}/site-packages/grpc_tools/protoc.py -I ./proto \
              --python_out=$out/lib/${python.libPrefix}/site-packages/ \
              --grpc_python_out=$out/lib/${python.libPrefix}/site-packages/ \
              proto/sal_services.proto
            popd

            substitute ${./aps/onie-syseeprom} $out/bin/onie-syseeprom \
              --subst-var-by PATH \
                "${lib.strings.makeBinPath [ coreutils i2c-tools gawk xz utillinux mount umount cpio gnused ]}"
            chmod a+x $out/bin/onie-syseeprom
          '';
        };
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  aps_bf2556 = {
    diff = "bf2556x_1t.diff";
    zipPattern = "*BF2556*.zip";
    CFLAGS = [
      "-Wno-error=unused-result"
      "-Wno-error=unused-variable"
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
