{ lib, callPackage, src, patches, version, ... }@args:

let
  derivation =

    { version, runCommand, stdenv, cmake, bf-syslibs, bf-drivers,
      bf-drivers-runtime, bf-utils, bf-utils-tofino, i2c-tools,
      ipmitool, thrift, boost, binutils-unwrapped, autoPatchelfHook,
      grpcForAPSSalRefApp, boost167, baseboard }:

    let
      src' = runCommand "bf-aps-${version}-bsp.tgz" {} ''
        tar xf ${src} --wildcards "*/packages" --strip-components 2
        mv bf-platforms* $out
      '';

      self = stdenv.mkDerivation {
        pname = "bf-platforms-${baseboard}";
        inherit version;
        src = src';
        patches = (patches.default or []) ++ (patches.${baseboard} or []);

        buildInputs = [ cmake bf-drivers.pythonModule bf-syslibs
                        bf-utils.dev bf-utils-tofino.dev bf-drivers
                        i2c-tools thrift boost ];

        cmakeFlags = [
          "-DSTANDALONE:BOOL=ON"
          "-DTHRIFT-DRIVER=ON"
        ];

        preConfigure = ''
          sed -i -e '/CMP0135/d' CMakeLists.txt
          substituteInPlace platforms/bf2556x-1t/src/ipmi/ipmi.c \
            --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
          substituteInPlace platforms/common/src/ipmi.c \
            --replace /usr/bin/ipmitool ${ipmitool}/bin/ipmitool
        '';

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
              in stdenv.mkDerivation {
                pname = "aps-sal-refapp";
                inherit version;
                inherit src;
                passthru = {
                  inherit salGrpcPort;
                };

                buildInputs = [ autoPatchelfHook self
                                grpcForAPSSalRefApp boost167 bf-syslibs
                                bf-drivers-runtime ];

                installPhase = ''
                  mkdir -p $out/bin
                  cp salRefApp $out/bin
                  chmod a+x $out/bin/salRefApp
                  mkdir $out/config
                  substitute ${../sal.ini} $out/config/sal.ini \
                    --subst-var-by GRPC_PORT ${salGrpcPort}
                  cp ${../logger.ini} -r $out/config/logger.ini
                '';
              };
          };
      };
    in self;
in {
  aps_bf2556 = callPackage derivation { baseboard = "aps_bf2556"; };
}
