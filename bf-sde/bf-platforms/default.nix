{ version, withAsic, bsps, lib, runCommand, callPackage, buildSupport }:

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
  bsps' = lib.recursiveUpdate bsps (lib.optionalAttrs (bsps ? "reference") {
    reference.src = buildSupport.fixupSrc {
      inherit src;
      preambleOverride = true;
      cmakeRules = ''
        list(APPEND CMAKE_MODULE_PATH "\''${CMAKE_CURRENT_SOURCE_DIR}/cmake")
      '';
    };
  });

  ## Each BSP creates a set of one or more baseboards
  baseboards = lib.mapAttrsToList (bspName: bsp:
    import (./. + "/${bspName}.nix") ({
      inherit bspName version lib callPackage;
      ## Some of the BSPs need to be merged with the reference BSP
      inherit (bsps') reference;
    } // bsp)
  ) bsps';

  baseboards' =
    if withAsic then
      ## This list contains a set for each supported baseboard derived
      ## from the BSP packages. A BSP can support multiple
      ## baseboards. For example, the reference BSP supports
      ## baseboards for Tofino1 ("accton") and Tofino2 ("newport") as
      ## well as a pseudo-baseboard for the Tofino model. Each build
      ## of a BSP produces a derivation that contains
      ## baseboard-specific files like the platform manager
      ## (libpltfm_mgr.so). The platform manager for the model signals
      ## to bf_switchd to use its non-ASIC mode of operation.
      baseboards
    else
      ## In non-ASIC mode, there are no BSPs and only the Tofino model
      ## is supported. In that case, we supply an empty
      ## derivation. The absence of libpltfm_mgr.so is interpreted by
      ## bf_switchd that it's running on the model. This is not
      ## exactly identical to the model-sepcific platform manager,
      ## e.g. the bfshell UCLI does not instantiate the bf_pltfm
      ## context. The difference is not relevant for running programs
      ## on the model.
      [
        {
          model = runCommand "bf-platforms-model-${version}" {} ''
            mkdir $out
          '';
        }
      ];
in
## Merge the baseboards into the final set
builtins.foldl' lib.mergeAttrs {} baseboards'
