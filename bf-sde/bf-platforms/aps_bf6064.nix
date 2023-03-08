{ ... }@args:

let
  lib = args.lib;
  version = args.version;
in if lib.versionOlder version "9.11.0"
   then
     import ./aps args
   else
     import aps/no-sal.nix args
