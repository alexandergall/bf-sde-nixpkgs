pkgs:

import ./release.nix { inherit pkgs; } // {
  mkOnieInstaller = import ./installers/onie { inherit pkgs; };
  mkStandaloneInstaller = pkgs.callPackage ./installers/standalone {};
  mkReleaseManager = pkgs.callPackage ./release-manager {};
}
