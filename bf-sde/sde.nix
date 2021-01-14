{ version, passthru, lib, buildEnv, bf-syslibs, bf-drivers, bf-utils, bf-platforms,
  p4c, tofino-model, tools }:

## This environment mimics the setup of the SDE/SDE_INSTALL tree of a
## regular installation of the SDE by merging the outputs of all
## packages.  This is needed for all parts of the SDE that expect to
## find things in certain places relative to SDE/SDE_INSTALL.

buildEnv {
  name = "bf-sde-${version}";
  inherit passthru;
  paths = [ bf-syslibs bf-drivers bf-drivers.dev bf-utils bf-platforms
            p4c tofino-model tools ];

  ## bfrt Python modules overlap in bfUtils and bfDrivers
  ignoreCollisions = lib.versionAtLeast version "9.3.0";
}
