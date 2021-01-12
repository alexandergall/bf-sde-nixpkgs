{ }:

let
  pkgs = import ./. {};
  ## Hydra doesn't like non-derivation attributes
  bf-sde = with pkgs.lib; filterAttrs (n: v: attrsets.isDerivation v) pkgs.bf-sde;
  kernels = import ./bf-sde/kernels pkgs.callPackage;
  modulesForSDE = sde:
    builtins.foldl' (result: kernelID: result // { ${kernelID} = sde.buildModules kernelID; }) {} (pkgs.lib.attrNames kernels);
  mk = sde: {
    inherit sde;
    inherit (sde) pkgs;
    kernelModules = modulesForSDE sde;
  };
  versions = pkgs.lib.mapAttrs (version: sde: mk sde) bf-sde;
in versions
