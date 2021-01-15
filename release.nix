## Used by the Hydra CI system to build all components for all
## SDE versions.
{ }:

let
  pkgs = import ./. {};
in with pkgs;
with lib;

let
  ## Hydra doesn't like non-derivation attributes
  bf-sde = filterAttrs (n: v: attrsets.isDerivation v) pkgs.bf-sde;
  kernels = import ./bf-sde/kernels pkgs;
  mk = sde: {
    inherit sde;
    inherit (sde) pkgs;
    kernelModules = mapAttrs (kernelID: _: sde.buildModules kernelID) kernels;
  };
  versions = mapAttrs (version: sde: mk sde) bf-sde;
in versions
