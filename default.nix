{ overlays ? [], ... } @attrs:

let
  nixpkgs = (fetchTarball https://github.com/NixOS/nixpkgs/archive/20.09-1181-gfee7f3fcb41.tar.gz);
in import nixpkgs ( attrs // {
  overlays = import ./overlay.nix ++ overlays;
})
