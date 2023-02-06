{ bf-sde, pkgs, platform }:

let
  expr = import (./. + "/${bf-sde.version}.nix");
in if (builtins.typeOf expr == "lambda")
   then
     (expr { inherit pkgs platform; })
   else
     expr
