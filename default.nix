{ overlays ? []

## The open-source version of the Intel SDE currently misses
## components related to the SerDes embedded on the ASIC that is still
## under NDA. As a consequence, only the Tofino software emulation
## ("Tofino model") is supported by default. However, there is a
## procedure documented in the "hw" subdirectory that merges the
## missing pieces from the original SDE with the open source code to
## re-create the full version. People who have signed the NDA and have
## access to the original archive bf-sde-9.13.4.tgz can enable this
## feature. The SDE archive needs to be added to the Nix store
## manually with
##
## $ nix-store --add-fixed sha256 archive bf-sde-9.13.4.tgz
##
## In that case, the reference BSP as well as any other BSP required
## for a particular platform need to be added as well.
, withAsic ? false

,  ...
} @attrs:

let
  nixpkgs = fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/23.11-6913-g205fd4226592.tar.gz;
    sha256 = "1f5d2g1p6nfwycpmrnnmc2xmcszp804adp16knjvdkj8nz36y1fg";
  };
  ## This repository uses a different version of nixpkgs. That's not a
  ## problem but increases the footprint of the SDE in the Nix store.
  p4lang-nixpkgs = pkgs.fetchFromGitHub {
    repo = "p4lang-nixpkgs";
    owner = "alexandergall";
    rev = "31ba99";
    hash = "sha256-Y8VHjkR3QNs7bnxbzPzwtfxBld2xHfuchPoq9481ogY=";
  };
  pkgs = import nixpkgs ( attrs // {
    overlays = (import ./overlay.nix) {
      inherit nixpkgs p4lang-nixpkgs withAsic;
    } ++ overlays;
  });
in pkgs
