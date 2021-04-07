## Used by the Hydra CI system to build all components for all
## SDE versions.
{ }:

let
  pkgs = import ./. {};
in
with pkgs;
with lib;

let
  filterDrvs = attrs:
    filterAttrs (n: v: attrsets.isDerivation v) attrs;
  ## Hydra doesn't like non-derivation attributes
  bf-sde' = filterDrvs bf-sde;
  kernels = import ./bf-sde/kernels pkgs;
  mk = sde: {
    inherit sde;
    inherit (sde) pkgs;
  };
  versions = mapAttrs (version: sde: mk sde) bf-sde';
in versions
