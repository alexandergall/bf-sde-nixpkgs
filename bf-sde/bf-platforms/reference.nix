{ version, lib, callPackage, src, patches, ... }:

let
  mkBaseboard = baseboard: { model ? false, newport ? false }:
    let
      derivation =
        { version, buildSupport, lib, stdenv, thrift, boost, libusb1,
          curl, target-syslibs, bf-drivers, bf-utils, target-utils,
          cmake, kernelSpec ? null, runtimeShell, kmod, coreutils }:

        assert kernelSpec != null -> newport;
        let
          stdenv' = if kernelSpec != null
                    then
                      kernelSpec.stdenv or stdenv
                    else
                      stdenv;
        in stdenv'.mkDerivation {
          pname = "bf-platforms-${baseboard}" + lib.optionalString (kernelSpec != null)
            "-kernel-modules-${kernelSpec.kernelRelease}";
          ## Note: src is the actual reference BSP archive, see
          ## default.nix
          inherit version src;
          patches = (patches.default or []) ++ (patches.${baseboard} or []);

          buildInputs = [ cmake bf-drivers.pythonModule thrift boost libusb1
                          curl target-syslibs bf-drivers target-utils bf-utils ];

          outputs = [ "out" "dev" ];
          enableParallelBuilding = true;
          ## The Newport platform libraries have unresolved references
          ## on (unused) functions, which is incompatible with the
          ## default immediate bindings used by mkDerivation. In
          ## addition, the platform library has unresolved references
          ## to Tofino3-specific functions.
          hardeningDisable = [ "bindnow" ];

          ## Newport requires a kernel module to drive the FPGA I2C
          ## controller. The module is created only when we are called
          ## with the build environment for a kernel. In that case,
          ## the derivation will *only* contain the module where as
          ## for the non-kernel build, the derivation will not contain
          ## the module or any part related to it.
          preConfigure =
            if (baseboard != "newport" || kernelSpec == null) then
              ''
                sed -i -e '/bf_fpga/d' CMakeLists.txt
              ''
            else
              ''
                sed -i -e 's/M=/foo=/g;s/src=/M=/g' platforms/newport/kdrv/bf_fpga/CMakeLists.txt
                sed -i 's/install(FILES ''${CMAKE_CURRENT_BINARY/install(FILES ''${CMAKE_CURRENT_SOURCE/' platforms/newport/kdrv/bf_fpga/CMakeLists.txt
              '';

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

          NIX_CFLAGS_COMPILE = lib.optional newport ([
            ## Make gcc recognize "fallthrough" pseudo-comments
            "-Wimplicit-fallthrough=3"
          ] ++ lib.optional (lib.versionAtLeast stdenv'.cc.version "14.0") [
            "-Wno-error=calloc-transposed-args"
          ]);

          postInstall =
          if (kernelSpec == null) then ''
              for file in $out/bin/*.sh; do
                substituteInPlace $file --replace ./cp2112 $out/bin/cp2112
              done
              python -m compileall $out/lib/${bf-drivers.pythonModule.libPrefix}/site-packages
            ''
          else
            ''
              shopt -s extglob
              rm -rf $out/lib/!(modules)
              rm -rf $out/bin/!(bf_fpga*)
              rm -rf $out/share
              shopt -u extglob
              mkdir $out/lib/modules/${kernelSpec.kernelRelease}
              mv $out/lib/modules/*.ko $out/lib/modules/${kernelSpec.kernelRelease}
            '' + import ../kernels/fixup-mod-loaders.nix {
              inherit (kernelSpec) kernelRelease;
              inherit runtimeShell kmod coreutils;
            };
        };
    in callPackage derivation {};
in lib.mapAttrs mkBaseboard {
  accton = {
  };
  newport = {
    newport = true;
  };
  model = {
    model = true;
  };
}
