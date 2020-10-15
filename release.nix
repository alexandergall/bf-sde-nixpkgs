{ }:

let
  pkgs = import ./. {};
  ## Hydra doesn't like non-derivation attributes
  bf-sde = with pkgs.lib; filterAttrs (n: v: attrsets.isDerivation v) pkgs.bf-sde;
in bf-sde
