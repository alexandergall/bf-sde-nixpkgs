{ pname, src, patches, bf-sde, pkgs, platform }:

let
  programs = (import ./compose.nix {
    inherit bf-sde pkgs platform;
  }).programs;
  build = p4Name:
    bf-sde.buildP4Program {
      pname = p4Name;
      version = "0";
      inherit src p4Name patches platform;
      path = "p4_16_programs/${p4Name}";
    };
in pkgs.lib.genAttrs programs build
