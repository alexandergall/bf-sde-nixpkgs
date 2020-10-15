{ version ? "all" }:

with import ./. {};
with lib;

if version == "all" then
  mapAttrs (n: v: v.support) (filterAttrs (n: v: attrsets.isDerivation v) bf-sde)
else
  bf-sde.${version}.support
