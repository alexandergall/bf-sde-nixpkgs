{ pname, src, patches, bf-sde, lib }:

let
  programs = (import (./. + "/${bf-sde.version}.nix")).programs;
  build = p4Name:
    bf-sde.buildP4Program {
      pname = p4Name;
      version = "0";
      inherit src p4Name patches;
      path = "p4_16_programs/${p4Name}";
    };
in lib.genAttrs programs build
