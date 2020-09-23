{ bf-sde, fetchgit, flavor, buildFlags }:

let
  repo = import ./repo.nix { inherit fetchgit; };
in bf-sde.buildP4Program rec {
  inherit (repo) version src;
  name = "RARE${if flavor == null then "" else "-${flavor}"}-${version}";
  p4Name = "bf_router";
  path = "p4src";
  inherit buildFlags;
}
