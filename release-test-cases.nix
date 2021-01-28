## Build example programs and run their test cases. This requires
## a lot of memory for parallel builds because each test is run in
## a VM with 6GB
## SDE versions.
{ }:

let
  pkgs = import ./. {};
in
with pkgs;
with lib;

let
  ## Hydra doesn't like non-derivation attributes
  bf-sde' = filterAttrs (n: v: attrsets.isDerivation v) bf-sde;
  mk = sde: {
    inherit (sde.test) programs;
  };
  versions = mapAttrs (version: sde: mk sde) bf-sde';
in versions
