{ overlays ? [], ... } @attrs:

let
  nixpkgsSrc = fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/22.05-1567-g099cb1a04e5.tar.gz;
    sha256 = "0pfqqsw97bflm1yby8xy697q2lkh7gp66ggcdwnjd5z1xy1y44vv";
  };
in import nixpkgsSrc ( attrs // {
  overlays = (import ./overlay.nix) nixpkgsSrc ++ overlays;
})
