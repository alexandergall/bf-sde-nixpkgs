{ }:

let
  pkgs = import ./.;
  ## Hydra doesn't like non-derivation attributes
  bf-sde = pkgs.lib.filterAttrs (n: v: n != "recurseForDerivations") pkgs.bf-sde;
in bf-sde
