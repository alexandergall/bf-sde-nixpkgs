{ version, bsps, lib, runCommand, callPackage, buildSystem }:

let
  ## The reference BSP archive contains the actual BSP as a separate
  ## archive.  We extract that archive here and replace the original
  ## archive with it. Also apply the fixup for CMake builds (the BSP
  ## is not actually standalone contrary to what the "STANDALONE"
  ## switch suggests).
  src = runCommand "bf-reference-bsp.tgz" {} ''
        tar xf ${bsps.reference.src} --wildcards "*/packages" --strip-components 2
        mv bf-platforms* $out
      '';
  bsps' = lib.recursiveUpdate bsps {
    reference.src = buildSystem.cmakeFixupSrc {
      inherit src;
      preambleOverride = true;
      cmakeRules = ''
        list(APPEND CMAKE_MODULE_PATH "\''${CMAKE_CURRENT_SOURCE_DIR}/cmake")
      '';
    };
  };

  ## Each BSP creates a set of one or more baseboards
  baseboards = lib.mapAttrsToList (bspName: bsp:
    import (./. + "/${bspName}.nix") ({
      inherit version lib callPackage;
      ## Some of the BSPs need to be merged with the reference BSP
      inherit (bsps') reference;
    } // bsp)
  ) bsps';

  ## Merge the baseboards into the final set
in builtins.foldl' lib.mergeAttrs {} baseboards
