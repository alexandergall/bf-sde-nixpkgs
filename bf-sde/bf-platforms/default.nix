{ bsps, lib, callPackage }:

let
  ## Each BSP creates a set of one or more baseboards
  baseboards = lib.mapAttrsToList (bspName: bsp:
    import (./. + "/${bspName}.nix") {
      inherit lib callPackage;
      inherit (bsp) src patches;
      ## Some of the BSPs need to be merged with the reference BSP
      inherit (bsps) reference;
    }
  ) bsps;

  ## Merge the baseboards into the final set
in builtins.foldl' lib.mergeAttrs {} baseboards
