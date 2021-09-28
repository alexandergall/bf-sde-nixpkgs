{ pkgs }:

{ nixProfile, partialSlice, platforms, version, component, NOS,
  bootstrapProfile, fileTree, binaryCaches, users ? {} }:

with builtins;
let
  mkOnieInstaller = pkgs.callPackage (pkgs.fetchgit {
    url = "https://github.com/alexandergall/onie-debian-nix-installer";
    rev = "80f192";
    sha256 = "191p68hwljjc1q7wzj9lx9asligzky50wa8mcqzw894bdzz62qw7";
  }) {};
  platformSpecs = map (
    platform:
      {
        profile = nixProfile + "-${platform}" + "/" + baseNameOf nixProfile;
        paths = attrValues (partialSlice platform);
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

  ## Add platform-dependent udev rules to the file tree
  addUdevRule = platform:
    let
      pciAddr = platformProperties.${platform}.mgmtEthPciAddr or null;
    in
      if pciAddr != null then
        ''
          dir=$out/__platforms/${platform}/etc/udev/rules.d
          mkdir -p $dir
          echo 'ACTION=="add", SUBSYSTEM=="net", KERNELS=="${pciAddr}", NAME="mgmt0"' >$dir/20-mgmt0.rules
        ''
      else
        "";
  fileTree' = pkgs.runCommand "file-tree-udev-rules" {} (''
    mkdir $out
    cp -r ${fileTree}/* $out
  '' +
  (with builtins; concatStringsSep "\n" (
    map addUdevRule platforms
  )));
in pkgs.lib.makeOverridable mkOnieInstaller {
  inherit version rootPaths users postRootFsCreateCmd postRootFsInstallCmd
    component NOS grubDefault bootstrapProfile binaryCaches;
  fileTree = fileTree';
}
