{ lib, callPackage, src, patches, reference, version, ... }:

import (
  if (lib.versionOlder version "9.9.0") then
    ## Older BSP that includes support for the "SAL" to driver the
    ## Marvell gear box
    aps/sal.nix
  else
    ./aps
) {
  inherit lib callPackage src patches reference version;
}
