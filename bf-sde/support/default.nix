self: nixpkgs: pkgs:

import ./release.nix { inherit pkgs; } // {
  mkOnieInstaller = pkgs.callPackage ./installers/onie { inherit self nixpkgs; };
  mkStandaloneInstaller = pkgs.callPackage ./installers/standalone {};
  mkReleaseManager = pkgs.callPackage ./release-manager {};
}
