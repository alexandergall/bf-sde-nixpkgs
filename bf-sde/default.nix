{ pkgs }:

with pkgs;

let
  ## Add a function to each SDE that compiles a given P4
  ## program in the context of the SDE.
  passthruFun = { self }:
    {
      buildP4Program = callPackage ./build-p4-program.nix {
        bf-sde = self;
      };
    };
  kernels = import ./kernels pkgs;
  mkSDE = sdeDef:
    let
      self = callPackage ./generic.nix ({
        inherit self kernels;
      } // sdeDef);
    in self;

## Download bf-sde-${version}.tar and bf-reference-bsp-${version}.tar
## from the BF FORUM repository and add them manually to the Nix store
##   nix-store --add-fixed sha256 <...>
## The hashes below are the "sha256sum" of these files.
in lib.mapAttrs (n: sdeDef: mkSDE (sdeDef // { inherit passthruFun; })) {
  v9_1_1 = {
    version = "9.1.1";
    srcHash = "be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11";
    bspHash = "aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8";
  };
  v9_2_0 = {
    version = "9.2.0";
    srcHash = "94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26";
    bspHash = "d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac";
  };
}
