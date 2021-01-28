## Build example programs and run their test cases. This requires
## a lot of memory for parallel builds because each test is run in
## a VM with 6GB.
## SDE versions.
{ }:

let
  pkgs = import ./. {};
in
with pkgs;
with lib;

let
  mk = sde: {
    inherit (sde.test) programs cases;
  };
  versions = mapAttrs (version: sde: mk sde) bf-sde;
in versions
