## Used by the Hydra CI system to build all components for all
## SDE versions.
{ nixpkgs ? null }:

let
  args =
    if nixpkgs == null then
      {}
    else
      { inherit nixpkgs; };
  pkgs = import ./. args;
in
with pkgs;
with lib;

let
  filterDrvs = attrs:
    filterAttrs (n: v: attrsets.isDerivation v) attrs;
  ## Hydra doesn't like non-derivation attributes
  bf-sde' = filterDrvs bf-sde;
  mk = sde:
    with builtins;
    let
      baseboards = attrNames sde.pkgs.bf-platforms;
      mkSdeForBoard = baseboard:
        nameValuePair
          "sde-${baseboard}"
          (sde.override { inherit baseboard; });
    in {
      inherit (sde) pkgs;
    } // listToAttrs (map mkSdeForBoard baseboards);
  versions = mapAttrs (version: sde: mk sde) bf-sde';
in versions
