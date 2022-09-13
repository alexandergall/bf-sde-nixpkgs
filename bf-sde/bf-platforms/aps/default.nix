{ lib, callPackage, src, patches, version, bspName, ... }@args:

let
  derivation =

    { version, runCommand, stdenv, cmake, curl, libusb, ipmitool,
      thrift, boost, bf-syslibs, bf-drivers, bf-utils,
      bf-utils-tofino, coreutils, i2c-tools, gawk, xz, utillinux,
      mount, umount, cpio, gnused,
      ## For salRefApp
      binutils-unwrapped, autoPatchelfHook, grpcForAPSSalRefApp,
      boost167, bf-drivers-runtime }:

    let
      src' = runCommand "bf-aps-${version}-bsp.tgz" {} ''
        tar xf ${src} --wildcards "*/packages" --strip-components 2
        mv bf-platforms* $out
      '';
      baseboard = bspName;
      self = stdenv.mkDerivation ({
        pname = "bf-platforms-${baseboard}";
        inherit version;
        src = src';
        patches = (patches.default or []) ++ (patches.${baseboard} or []);

        buildInputs =
          if (lib.versionOlder version "9.9.0") then
            [ cmake curl libusb ipmitool thrift boost
              bf-syslibs bf-drivers bf-utils.dev coreutils ]
          else
            [ cmake bf-drivers.pythonModule bf-syslibs
              bf-utils.dev bf-utils-tofino.dev bf-drivers
              i2c-tools thrift boost ];

        cmakeFlags =
          lib.optional (lib.versionOlder version "9.9.0") "-DASIC=ON" ++
          [
            "-DSTANDALONE=ON"
            "-DTHRIFT-DRIVER=ON"
          ];

        preConfigure =
          if (lib.versionOlder version "9.9.0") then
            (''
               sed -i '1 i\cmake_policy(SET CMP0048 NEW)\nproject(APSNNetworksBSP VERSION ${version})' CMakeLists.txt
              '' + lib.optionalString (baseboard == "aps_bf2556") ''
                for f in platforms/apsn/src/util/apsn_pltfm_util.c \
                         platforms/apsn/src/bf_pltfm_chss_mgmt/bf_pltfm_chss_mgmt_ps.c \
                         platforms/apsn/src/bf_pltfm_chss_mgmt/bf_pltfm_chss_mgmt_fan.c; do
                  substituteInPlace $f \
                    --replace "sudo ipmitool" ${ipmitool}/bin/ipmitool
                done
                substituteInPlace platforms/apsn/src/bf_pltfm_chss_mgmt/bf_pltfm_chss_mgmt_ps.c \
                  --replace "sudo i2cget" ${i2c-tools}/bin/i2cget
                substituteInPlace platforms/apsn/src/bf_pltfm_chss_mgmt/bf_pltfm_bd_eeprom.c \
                  --replace onie-syseeprom $out/bin/onie-syseeprom
              '')
          else
            (''
               sed -i -e '/CMP0135/d' CMakeLists.txt
             '' + lib.optionalString (baseboard == "aps_bf2556") ''
               substituteInPlace platforms/bf2556x-1t/src/ipmi/ipmi.c \
                 --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
               substituteInPlace platforms/common/src/ipmi.c \
                 --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
              '');

        postInstall = lib.optionalString (lib.versionOlder version "9.9.0" &&
                                          baseboard == "aps_bf2556") ''
          substitute ${./onie-syseeprom} $out/bin/onie-syseeprom \
            --subst-var-by PATH \
            "${lib.strings.makeBinPath [ coreutils i2c-tools gawk xz utillinux mount umount cpio gnused ]}"
          chmod a+x $out/bin/onie-syseeprom
        '';
      } // (lib.optionalAttrs (baseboard == "aps_bf2556") {
        ## This package contains only the salRefApp pre-built binary
        ## treated with autoPatchelf.
        passthru =
          let
            salDebianPkg = args.salDebianPkg;
            patches = (salDebianPkg.patches.default or []) ++
                      (salDebianPkg.patches.${baseboard} or []);
            src = runCommand "sal-source" {
              inherit patches;
            } ''
              ${binutils-unwrapped}/bin/ar x ${salDebianPkg.src}
              mkdir $out
              tar -C $out -xf data.tar.gz --strip-components=4
              cd $out
              for patch in $patches; do
                patch -p1 <$patch
              done
            '';
          in {
            salRefApp =
              let
                salGrpcPort = "50053";
                python = bf-drivers.pythonModule;
              in stdenv.mkDerivation {
                pname = "aps-sal-refapp";
                inherit version;
                inherit src;
                passthru = {
                  inherit salGrpcPort;
                };

                buildInputs = [ self autoPatchelfHook
                                grpcForAPSSalRefApp boost167
                                bf-syslibs bf-drivers-runtime ];

                installPhase = ''
                  mkdir -p $out/bin
                  cp salRefApp $out/bin
                  chmod a+x $out/bin/salRefApp
                  mkdir $out/config
                  substitute ${./sal.ini} $out/config/sal.ini \
                    --subst-var-by GRPC_PORT ${salGrpcPort}
                  cp ${./logging.toml} -r $out/config/logging.toml

                  sitePath=$out/lib/${python.libPrefix}/site-packages
                  mkdir -p $sitePath
                  ${python.pkgs.grpcio-tools}/lib/${python.libPrefix}/site-packages/grpc_tools/protoc.py -I ./proto \
                    --python_out=$sitePath/ \
                    --grpc_python_out=$sitePath/ \
                    proto/sal_services.proto
                '';
              };
          };
      }));
    in self;
in {
  "${bspName}" = callPackage derivation {};
}
