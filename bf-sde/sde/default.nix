## Create the full SDE or a slimmed-down runtime version. The output
## is a user environment that contains all the components just like
## what p4studio produces.  The run_* tools are already wrapped in
## shell scripts that set the SDE and SDE_INSTALL environment
## variables.
##
## The runtime version only contains the components necessary to run
## compiled P4 programs.
##
## If called without kernelID, the environment does not contain any
## kernel modules. Otherwise, the kernel modules for the given kernel
## are added to the environment. This includes all baseboard-sepcific
## modules and related tools (if any).

{ runtime ? false, baseboard, version, src, patches, passthru ? {},
  lib, stdenv, buildEnv, callPackage, target-syslibs, bf-drivers,
  bf-drivers-runtime, target-utils, bf-platforms, p4c, tofino-model,
  ptf-modules, ptf-utils, ptf-utils-runtime, kernelID ? null, kernel-modules
}:

let
  paths =
    (if runtime then
      ## ptf-utils-runtime is required by run_bfshell.sh
      [ target-syslibs bf-drivers-runtime target-utils ptf-utils-runtime ]
      ++ lib.optional (baseboard == "model") tofino-model
     else
       [ target-syslibs bf-drivers target-utils p4c
         tofino-model ptf-modules ptf-utils ])
    ++ lib.optional (baseboard != null)
      (assert lib.asserts.assertMsg (builtins.hasAttr baseboard bf-platforms)
        "Baseboard ${baseboard} not supported by SDE ${version}";
        bf-platforms.${baseboard})
    ++ lib.optional (kernelID != null && baseboard != null)
      (kernel-modules.${kernelID}.override { inherit baseboard; });

  ## Additional things from the SDE source that need to go into
  ## sdeEnv.
  addToEnv = stdenv.mkDerivation {
    pname = "bf-sde-misc-components";
    inherit version src;
    patches = patches.mainCMake or [];
    phases = [ "unpackPhase" "patchPhase" "installPhase" ];
    installPhase = ''
      mkdir $out
      mkdir -p $out/share
      ## This is displayed by the "version" command in bfshell
      echo ${version} >$out/share/VERSION
    '' + lib.optionalString (! runtime) ''
      mkdir $out/p4_build
      cp p4studio/CMakeLists.txt $out/p4_build
      cp -r cmake $out/p4_build
      mkdir -p $out/pkgsrc/p4-examples
      cp -r pkgsrc/p4-examples/tofino* $out/pkgsrc/p4-examples
    '';
  };
  maybeRuntime = lib.optionalString runtime "-runtime";
  maybeBaseboard =
    if baseboard == null then
      "-bspless"
    else
      "-${baseboard}";
  sdeEnv = buildEnv {
    name = "bf-sde" + maybeBaseboard + maybeRuntime + "-env-${version}";
    paths = paths ++ [ addToEnv ];
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
