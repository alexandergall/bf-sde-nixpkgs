self: nixpkgsSrc: pkgs:

import ./release.nix { inherit pkgs; } // {
  mkOnieInstaller = pkgs.callPackage ./installers/onie { inherit self nixpkgsSrc; };
  mkStandaloneInstaller = pkgs.callPackage ./installers/standalone {};
  mkReleaseManager = pkgs.callPackage ./release-manager {};
}
