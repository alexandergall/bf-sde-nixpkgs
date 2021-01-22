{ version, lib, buildEnv, bf-syslibs,
  bf-drivers, bf-utils, bf-platforms, tools }:
   
buildEnv {
  name = "bf-sde-${version}-runtime";
  paths = [ bf-syslibs bf-drivers bf-utils bf-platforms tools ];
  ignoreCollisions = lib.versionAtLeast version "9.3.0";
}
