{ overlays ? [], ... } @attrs:

let
  nixpkgsSrc = fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/20.09-1181-gfee7f3fcb41.tar.gz;
    sha256 = "14zbi500kh2hl77kj0mskn79yn0gnk8jnb5l6misla6ha8qr3d46";
  };
in import nixpkgsSrc ( attrs // {
  overlays = (import ./overlay.nix) nixpkgsSrc ++ overlays;
})
