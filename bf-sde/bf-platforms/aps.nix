{ lib, callPackage, src, patches, reference }:

let
  ## This derivation uses the reference BSP as source and merges the
  ## APS BSP into it.
  mkBaseboard = baseboard: { diff, pattern, CFLAGS }:
    let
      derivation =
        { runCommand, version, buildSystem, unzip, stdenv, buildEnv,
          thrift, boost, libusb, curl, coreutils, bf-syslibs,
          bf-drivers, bf-drivers-runtime, bf-utils, cmake, autoconf,
          automake115x, autoPatchelfHook, boost167,
          grpcForAPSSalRefApp, i2c-tools, gawk, xz, utillinux, mount,
          umount, cpio, gnused }:

        let
          ## This is the full "APS One Touch" package. It contains the
          ## BSPs in the bsp directory, either zipped or plain.
          src' = runCommand "aps-unpack-bsp" {} ''
            mkdir $out
            cd $out
            ${unzip}/bin/unzip ${src}
          '';
          python = bf-drivers.pythonModule;

          ## This is the platform package without the salRefApp binary
          self = stdenv.mkDerivation {
            pname = "bf-platforms-${baseboard}";
            inherit version CFLAGS passthru;
            inherit (reference) src;

            buildInputs =
              [ python thrift boost libusb curl unzip
                bf-syslibs.dev bf-drivers.dev bf-utils ] ++
              (if buildSystem.isCmake then
                [ cmake ]
               else
                 [ autoconf automake115x ]);

            outputs = [ "out" "dev" ];
            enableParallelBuilding = true;

            preConfigure =
              ## Merge the APS BSP with the reference BSP
              ''
                mkdir bf-platforms
                tar -C bf-platforms -xf packages/bf-platforms* --strip-components 1
                cd bf-platforms
                if [ -n "$(shopt -s nullglob; echo ${src'}/bsp/${pattern}.zip)" ]; then
                  unzip ${src'}/bsp/${pattern}.zip
                else
                  cp -r ${src'}/bsp/${pattern}/* .
                  chmod -R a+w .
                fi
                if [ -f ${diff} ]; then
                  patch -p1 <${diff}
                fi
                for patch in ${builtins.concatStringsSep " " ((patches.default or []) ++ (patches.${baseboard} or []))}; do
                  patch -p1 <$patch
                done

                substituteInPlace platforms/apsn/src/bf_pltfm_chss_mgmt/bf_pltfm_bd_eeprom.c \
                  --replace onie-syseeprom $out/bin/onie-syseeprom
              '' + buildSystem.preConfigure {
                package = "bf-platforms";
                preCmds = ''
                  substituteInPlace CMakeLists.txt --replace "PROJECT_SOURCE_DIR}" "PROJECT_SOURCE_DIR}/\''${BF_PKG_DIR}/bf-platforms"
                  export SDE_INSTALL=$out
                '';
                cmakeRules = ''
                  find_package(Thrift REQUIRED)
                  add_subdirectory(''${BF_PKG_DIR}/bf-platforms)
                '';
              };

            cmakeFlags = [
              "-DSTANDALONE=OFF"
              "-DASIC=ON"
              "-DNEWPORT=OFF"
              "-DACCTON=OFF"
              "-DAPSN=ON"
              "-DACCTON-DIAGS=OFF"
              "-DNEWPORT-DIAGS=OFF"
            ];

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

              ## Generate the gRPC python bindings for the SAL
              pushd ${src'}/APS-One-touch*/release/sal*
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

          ## This package contains only the salRefApp pre-built binary
          ## treated with autoPatchelf.  It is built separately from
          ## the APS platform package above because it requires some
          ## of the shared libraries from there for patchelf. Lumping
          ## it all together would result in unnecessary work for
          ## autoPatchelf. It also produces a bad RPATH for
          ## libstdc++.so.6 for the 9.7.0 version of the package.
          passthru = lib.optionalAttrs (baseboard == "aps_bf2556") {
            salRefApp =
              let
                salGrpcPort = "50053";
              in stdenv.mkDerivation {
                pname = "aps-sal-refapp";
                inherit version;
                src = src';
                passthru = {
                  inherit salGrpcPort;
                };
                buildInputs = [ autoPatchelfHook self grpcForAPSSalRefApp boost167 bf-drivers-runtime ];
                installPhase = ''
                  mkdir -p $out/bin
                  cp APS-One-touch*/release/sal*/build/salRefApp $out/bin
                  chmod a+x $out/bin/salRefApp
                  mkdir $out/config
                  substitute ${aps/sal.ini} $out/config/sal.ini \
                    --subst-var-by GRPC_PORT ${salGrpcPort}
                  cp ${aps/logger.ini} -r $out/config/logger.ini
                '';
              };
          };
        in self;
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  aps_bf2556 = {
    diff = "bf2556x_1t.diff";
    pattern = "*BF2556*";
    CFLAGS = [
      "-Wno-error=unused-result"
      "-Wno-error=unused-variable"
      "-Wno-error=format"
    ];
  };
  aps_bf6064 = {
    diff = "bf6064x_t.diff";
    pattern = "*BF6064*";
    CFLAGS = [
      "-Wno-error=maybe-uninitialized"
      "-Wno-error=sizeof-pointer-memaccess"
    ];
  };
}
