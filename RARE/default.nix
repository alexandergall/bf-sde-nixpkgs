import ../nixpkgs {
  overlays =
    import ../overlay.nix ++
    import ./overlay.nix;
}
