{ overlays ? [], ... } @attrs:

import ./nixpkgs ( attrs // {
  overlays = overlays ++ import ./overlay.nix;
})
