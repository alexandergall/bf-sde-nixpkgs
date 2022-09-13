## Create the full SDE or a slimmed-down runtime version. The output
## is a user environment that contains all the components just like
## what p4studio produces.  The run_* tools are already wrapped in
## shell scripts that set the SDE and SDE_INSTALL environment
## variables.
##
## The runtime version only contains the components necessary to run
## compiled P4 programs (see ../build-p4-program.nix). It respects the
## rules concerning the distribution of SDE components to third
## parties imposed by Intel.

{ runtime ? false, baseboard, version, src, patches, passthru ? {},
  lib, stdenv, buildEnv, callPackage, bf-syslibs, bf-drivers,
  bf-drivers-runtime, bf-utils, bf-platforms, p4c, tofino-model,
  ptf-modules, ptf-utils, ptf-utils-runtime }:

let
  ## The BSP for the APS 2556X-1T currently requires a modified
  ## bf-drivers package on 9.9.0. We make these specific overrides
  ## here and hope that they will go away in future versions.
  bf-drivers' =
    if (baseboard == "aps_bf2556" && lib.versionAtLeast version "9.9.0") then
      bf-drivers.overrideAttrs (oldAttrs: {
        patches = oldAttrs.patches ++ [ ../bf-drivers/aps-efuse.patch ];
      })
    else
      bf-drivers;
  bf-drivers-runtime' = bf-drivers'.override { runtime = true ; };
  paths =
    (if runtime then
      ## ptf-utils-runtime is required by run_bfshell.sh
      [ bf-syslibs bf-drivers-runtime' bf-utils ptf-utils-runtime ]
      ++ lib.optional (baseboard == "model") tofino-model
     else
       [ bf-syslibs bf-drivers' bf-drivers.dev bf-utils bf-utils.dev
         p4c tofino-model ptf-modules ptf-utils ])
    ++ lib.optional (baseboard != null)
      (assert lib.asserts.assertMsg (builtins.hasAttr baseboard bf-platforms)
        "Baseboard ${baseboard} not supported by SDE ${version}";
        bf-platforms.${baseboard});

  ## Additional things from the SDE source that need to go into
  ## sdeEnv.
  addToEnv = stdenv.mkDerivation {
    pname = "bf-sde-misc-components";
    inherit version src;
    patches = patches.mainCMake or [];
    phases = [ "unpackPhase" "installPhase" ];
    installPhase = ''
      mkdir $out
      cp *manifest $out

    '' + lib.optionalString (! runtime)
      (if (lib.versionOlder version "9.7.0") then ''
         mkdir -p $out/pkgsrc/p4-build
         tar -C $out/pkgsrc/p4-build -xf packages/p4-build* --strip-component 1
         chmod a+x $out/pkgsrc/p4-build/tools/*
        ''
       else ''
         mkdir $out/p4_build
         cp p4studio/CMakeLists.txt $out/p4_build
         cp -r cmake $out/p4_build
       '') + ''

      mkdir -p $out/pkgsrc/p4-examples
      tar -C $out/pkgsrc/p4-examples -xf packages/p4-examples* \
          --wildcards "p4-examples*/tofino*" --strip-components 1
    '';
  };
  maybeRuntime = lib.optionalString runtime "-runtime";
  maybeBaseboard = lib.optionalString (baseboard != null) "-${baseboard}";
  sdeEnv = buildEnv {
    name = "bf-sde" + maybeBaseboard + maybeRuntime + "-env-${version}";
    paths = paths ++ [ addToEnv ];

    ## bfrt Python modules overlap in bfUtils and bfDrivers
    ignoreCollisions = lib.versionAtLeast version "9.3.0";
  };
  tools = callPackage ./tools.nix {
    inherit src version sdeEnv runtime baseboard;
    patches = patches.mainTools or [];
    python = bf-drivers.pythonModule;
  };
in buildEnv {
  name = "bf-sde" + maybeBaseboard + maybeRuntime + "-${version}";
  inherit passthru;
  paths = [ sdeEnv tools ];
}
