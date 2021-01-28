{ bf-sde, pkgs, srcSpec }:

with pkgs;
let
  test = import (./. + "/${bf-sde.version}.nix");
  ## Unpack and patch the p4-examples sources
  src = stdenv.mkDerivation {
    name = "p4-examples-source";
    inherit (srcSpec) src patches;
    configurePhase = "true";
    buildPhase = "true";
    installPhase = ''
      mkdir $out
      tar cf - . | tar -C $out -xf -
    '';
  };
  mkTest = name:
    let
      p4Name = name;
      path = "p4_16_programs/${name}";
      program = bf-sde.buildP4Program {
        pname = name;
        version = "0";
        inherit src p4Name path;
      };
    in program.runTest ({
      self = program;
      inherit src p4Name;
      testDir = path;
    } // test.args.${name} or {});
in lib.genAttrs test.programs mkTest
