## Build example programs for all versions and all targets.  Ideally,
## we would also run the test cases themselves but that requires a lot
## of memory for parallel builds because each test is run in a VM with
## 6GB.
{ ... }@args:

let
  pkgs = import ./. args;
in
with pkgs;
with lib;

let
  ## Hydra doesn't like non-derivation attributes
  bf-sde' = filterAttrs (n: v: attrsets.isDerivation v) bf-sde;
  mk = sde:
    mapAttrs (target: attrs:
      {
        inherit (attrs) programs;
      }
    ) sde.test;
  versions = mapAttrs (version: sde: mk sde) bf-sde';
in versions
