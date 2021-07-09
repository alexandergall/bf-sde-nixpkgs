{ pkgs }:

{ version, nixProfile, slice, platforms, component, NOS,
  bootstrapProfile, fileTree }:

with builtins;
let
  mkOnieInstaller = pkgs.callPackage (pkgs.fetchgit {
    url = "https://github.com/alexandergall/onie-debian-nix-installer";
    rev = "7edce3";
    sha256 = "168ymx85vi3yk52cl56vw83rsbdw4gy3gyh7h7sdqyrmg9jyzr23";
  }) {};
  platformSpecs = map (
    platform:
      {
        profile = nixProfile + "-${platform}" + "/" + baseNameOf nixProfile;
        paths = attrValues (slice platform);
      }
  ) platforms;
  rootPaths = (pkgs.lib.foldAttrs (final: paths: final ++ paths) [] platformSpecs).paths;

  installProfile = platformSpec:
    let
      profile = platformSpec.profile;
      paths = platformSpec.paths;
    in ''
      echo "Installing paths in ${profile}"
      mkdir -p $(dirname ${profile})
      ## Without setting HOME, nix-env creates /homeless-shelter to create
      ## a link for the Nix channel. That confuses the builder, which insists
      ## that the directory does not exist.
      HOME=/tmp
      /nix/var/nix/profiles/default/bin/nix-env -p ${profile} -i \
        ${pkgs.lib.strings.concatStringsSep " " paths} --option sandbox false
    '';

  ## Create separate profiles for all supported platforms in the root
  ## fs.
  postRootFsCreateCmd = pkgs.writeShellScript "install-profiles"
    (pkgs.lib.concatStrings (map installProfile platformSpecs));
  ## At installation time, select the profile for the target system as
  ## the actual profile and remove all other platform profiles.
  postRootFsInstallCmd = pkgs.callPackage ./post-install-cmd.nix { inherit nixProfile; };

  platformProperties = import ../../../bf-platforms/properties.nix;
  mkGrubDefault = platform:
    let
      properties = platformProperties.${platform};
    in {
      ${platform} = builtins.toFile "grub-default-${platform}" ''
        GRUB_DEFAULT=0
        GRUB_TIMEOUT=5
        GRUB_CMDLINE_LINUX_DEFAULT="console=${properties.serialDevice},${properties.serialSettings}"
        GRUB_CMDLINE_LINUX=""
        GRUB_TERMINAL="console"
      '';
    };
  grubDefault = builtins.foldl' (final: next: final // mkGrubDefault next) {} platforms;
in mkOnieInstaller {
  memSize = 5*1024;
  inherit version rootPaths postRootFsCreateCmd postRootFsInstallCmd
    component NOS grubDefault bootstrapProfile fileTree;
  binaryCaches = [ {
    url = "http://p4.cache.nix.net.switch.ch";
    key = "p4.cache.nix.net.switch.ch:cR3VMGz/gdZIdBIaUuh42clnVi5OS1McaiJwFTn5X5g=";
  } ];
}
