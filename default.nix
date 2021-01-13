{ overlays ? [], ... } @attrs:

let
  nixpkgs = (fetchTarball https://github.com/NixOS/nixpkgs/archive/19.03-1562-g34c7eb7545d.tar.gz);
in import nixpkgs ( attrs // {
  overlays = import ./overlay.nix ++ overlays;
})
