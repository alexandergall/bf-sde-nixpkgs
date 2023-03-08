## Starting with 9.11, APS has redesigned the BSP for the
## stordis_bf2556x_1t platform to no longer use the "SAL" to manage
## the gearbox. The SAL used to be a wrapper around bf_switchd which
## required a number of modifications in other parts of the SDE. The
## new version reverts to a traditional standalone bf_switchd process
## with a new binary that handles the gearbox and is intended to be
## run as an independent daemon.

{ lib, callPackage, src, patches, version, bspName, aps_gearbox ?
  null, aps_igb ? null, aps_irq ? null, ... }@args:

let
  derivation =

    { version, runCommand, stdenv, cmake, thrift, i2c-tools, boost,
      bf-utils, bf-utils-tofino, bf-syslibs, bf-drivers }:
    
    let
      gearbox = callPackage ./gearbox.nix { inherit aps_gearbox; };
      ## A variant of the intel igb driver that is supposed to work
      ## around an issue on the BF6064X-T
      igb = callPackage ./igb.nix { inherit aps_igb; };
      ## A kernel module required to signal port presence events to
      ## bf_switchd on the BF2556X-1T
      irq = callPackage ./irq.nix { inherit aps_irq; };
      baseboard = bspName;
    in stdenv.mkDerivation {
      pname = "bf-platforms-${baseboard}";
      inherit version;
      src = runCommand "bf-aps-${version}-bsp.tgz" {} ''
        tar xf ${src} --wildcards "*/packages" --strip-components 2
        mv bf-platforms* $out
      '';
      outputs = [ "out" "dev" ];
      patches = (patches.default or []) ++ (patches.${baseboard} or []);

      passthru = if (bspName == "aps_bf2556")
                 then {
                   inherit gearbox irq;
                 }
                 else {
                   inherit igb;
                 };

      buildInputs = [ cmake thrift i2c-tools boost bf-utils
                      bf-utils-tofino bf-syslibs bf-drivers ];

      cmakeFlags = [
        "-DSTANDALONE=ON"
        "-DTHRIFT-DRIVER=ON"
      ];

      preConfigure = ''
        sed -i '/CMP0135/d' CMakeLists.txt
        head CMakeLists.txt
      '';
      };
in {
  "${bspName}" = callPackage derivation {};
}
