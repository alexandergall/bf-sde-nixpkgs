{ overlays ? [], ... } @attrs:

import ./nixpkgs ( attrs // {
  overlays = import ./overlay.nix ++ overlays;
})
