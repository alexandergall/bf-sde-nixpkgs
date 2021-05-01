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

{ runtime, version, src, passthru ? {}, lib, stdenv, buildEnv, callPackage,
  bf-syslibs, bf-drivers, bf-drivers-runtime,  bf-utils,
  bf-platforms, p4c, tofino-model, ptf-modules, ptf-utils }:

let
  paths = if runtime then
            ## ptf-utils is required by run_bfshell.sh
            [ bf-syslibs bf-drivers-runtime bf-utils bf-platforms ptf-utils ]
          else
            [ bf-syslibs bf-drivers bf-drivers.dev bf-utils bf-utils.dev
              bf-platforms p4c tofino-model ptf-modules ptf-utils ];

  ## Additional things from the SDE source that need to go into
  ## sdeEnv.
  addToEnv = stdenv.mkDerivation {
    pname = "bf-sde-misc-components";
    inherit version src;
    phases = [ "unpackPhase" "installPhase" ];
    installPhase = ''
      mkdir $out
      cp *manifest $out

    '' + lib.optionalString (! runtime) ''

      mkdir -p $out/pkgsrc/p4-build
      tar -C $out/pkgsrc/p4-build -xf packages/p4-build* --strip-component 1
      chmod a+x $out/pkgsrc/p4-build/tools/*

      mkdir -p $out/pkgsrc/p4-examples
      tar -C $out/pkgsrc/p4-examples -xf packages/p4-examples* \
          --wildcards "p4-examples*/tofino*" --strip-components 1
    '';
  };
  maybeRuntime = lib.optionalString runtime "-runtime";
  sdeEnv = buildEnv {
    name = "bf-sde" + maybeRuntime + "-env-${version}";
    paths = paths ++ [ addToEnv ];

    ## bfrt Python modules overlap in bfUtils and bfDrivers
    ignoreCollisions = lib.versionAtLeast version "9.3.0";
  };
  tools = callPackage ./tools.nix { inherit src version sdeEnv runtime; };
in buildEnv {
  name = "bf-sde" + maybeRuntime + "-${version}";
  inherit passthru;
  paths = [ sdeEnv tools ];
}
