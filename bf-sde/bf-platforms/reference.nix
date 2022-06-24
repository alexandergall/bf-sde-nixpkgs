{ version, lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: { model ? false, newport ? false }:
    let
      derivation =
        { version, buildSystem, lib, stdenv, thrift, boost, libusb,
          curl, bf-syslibs, bf-drivers, bf-utils, bf-utils-tofino,
          cmake, kernelSpec ? null, runtimeShell, kmod, coreutils }:

        assert kernelSpec != null -> newport;
        stdenv.mkDerivation ({
          pname = "bf-platforms-${baseboard}" + lib.optionalString (kernelSpec != null)
            "-kernel-modules-${kernelSpec.kernelRelease}";
          ## Note: src is the actual reference BSP archive, see
          ## default.nix
          inherit version src;
          patches = (patches.default or []) ++ (patches.${baseboard} or []);

          buildInputs = [ bf-drivers.pythonModule thrift boost libusb
                          curl bf-syslibs.dev bf-drivers.dev bf-utils
                          ] ++ lib.optional buildSystem.isCmake [
                            cmake ] ++
                          lib.optionals (lib.versionAtLeast version "9.9.0")
                            [ bf-utils-tofino.dev ];

          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;
          ## The Newport platform libraries have unresolved references
          ## on (unused) functions, which is incompatible with the
          ## default immediate bindings used by mkDerivation.
          hardeningDisable = lib.optional newport "bindnow";

          ## Newport requires a kernel module to drive the FPGA I2C
          ## controller. The module is created only when we are called
          ## with the build environment for a kernel. In that case,
          ## the derivation will *only* contain the module where as
          ## for the non-kernel build, the derivation will not contain
          ## the module or any part related to it.
          preConfigure = lib.optionalString (baseboard == "newport" && kernelSpec == null) ''
            sed -i -e '/bf_fpga/d' CMakeLists.txt
          '';

          configureFlags = lib.optional (! buildSystem.isCmake)
            (if model then
              [ "--with-model" ]
             else
               [ "--with-tofino" ]) ++
            [ "enable_thrift=yes" ];

          postInstall =
          if (kernelSpec == null) then ''
              for file in $out/bin/*.sh; do
                substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
              done
            '' + lib.optionalString buildSystem.isCmake ''
              python -m compileall $out/lib/${bf-drivers.pythonModule.libPrefix}/site-packages
            ''
          else
            ''
              shopt -s extglob
              rm -rf $out/lib/!(modules)
              rm -rf $out/bin/!(bf_fpga*)
              shopt -u extglob
              mkdir $out/lib/modules/${kernelSpec.kernelRelease}
              mv $out/lib/modules/*.ko $out/lib/modules/${kernelSpec.kernelRelease}
            '' + import ../kernels/fixup-mod-loaders.nix {
              inherit (kernelSpec) kernelRelease;
              inherit runtimeShell kmod coreutils;
            };
        } // lib.optionalAttrs buildSystem.isCmake {
          cmakeFlags =
            (if model then
              [ "-DASIC=OFF" ]
             else
               [ "-DASIC=ON" ]) ++
            [ "-DSTANDALONE=ON" ] ++
            lib.optional newport [
              "-DNEWPORT=ON"
            ] ++
            lib.optional (kernelSpec != null) [
              "-DKDIR=${kernelSpec.buildTree}"
            ];
        });
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard ({
  accton = {
  };
  model = {
    model = true;
  };
} // lib.optionalAttrs (lib.versionAtLeast version "9.7.0") {
  newport = {
    newport = true;
  };
})
