{ self, nixpkgsSrc, lib, callPackage, fetchgit, writeShellScript, runCommand }:

{ nixProfile, slice, platforms, version, component, NOS,
  bootstrapProfile, fileTree, binaryCaches, users ? {},
  activate ? true, withSdeEnv ? false }:

with builtins;
let
  mkOnieInstaller = callPackage (fetchgit {
    url = "https://github.com/alexandergall/onie-debian-nix-installer";
    rev = "fc5a4d";
    sha256 = "0lc3r62sls7vfbmgcx4kisr5lvqfbgl88kvin5zdsgrc5gmz45wl";
  }) {};
  platforms' = filter (platform: builtins.match "^model.*" platform == null) platforms;
  kernelID = import (bootstrapProfile + "/kernelID.nix");
  kernelModules =
    assert lib.assertMsg (hasAttr kernelID self.pkgs.kernel-modules)
      "The bootstrap kernel ID ${kernelID} is not supported by SDE ${self.version}";
    self.pkgs.kernel-modules.${kernelID};
  platformRootPaths = platform:
    attrValues (slice kernelModules platform);
  mkSdeEnvInputDrv = platform:
    (self.mkShell {
      inherit platform kernelID;
    }).inputDerivation;
  mkSdeEnvGcRoot = platform:
    writeShellScript "mk-sde-env-gc-root-${platform}" ''
      echo "Adding GC root for SDE shell, platform ${platform}"
      mkdir -p /nix/var/nix/gcroots/per-user/root/sde-env
      ln -s ${mkSdeEnvInputDrv platform} /nix/var/nix/gcroots/per-user/root/sde-env/${platform}.tmp
    '';
  rootPaths =
    (foldl' (paths: platform: paths ++ (platformRootPaths platform)) [] platforms')
    ++ lib.optionals withSdeEnv (
      (map mkSdeEnvInputDrv platforms')
      ++ [ self.envCommand nixpkgsSrc ]
    );
  installProfile = platform:
    let
      profile = nixProfile + "-${platform}" + "/" + baseNameOf nixProfile;
      paths = platformRootPaths platform;
    in ''
      echo "Installing paths in ${profile}"
      mkdir -p $(dirname ${profile})
      ## Without setting HOME, nix-env creates /homeless-shelter to create
      ## a link for the Nix channel. That confuses the builder, which insists
      ## that the directory does not exist.
      HOME=/tmp
      /nix/var/nix/profiles/default/bin/nix-env -p ${profile} -i \
        ${lib.strings.concatStringsSep " " paths} --option sandbox false
    '';
  installProfiles = writeShellScript "install-profiles"
    (lib.concatStrings (map installProfile platforms'));

  ## Create separate profiles for all supported platforms in the root
  ## fs, optionally add GC roots and the sde-env command if withSdeEnv
  ## is requested
  postRootFsCreateCmds =
    lib.optional (nixProfile != null) installProfiles ++
    lib.optionals withSdeEnv (
      (map mkSdeEnvGcRoot platforms') ++
      lib.singleton (writeShellScript "install-env-command" ''
         ln -s ${nixpkgsSrc} /nix/var/nix/gcroots/per-user/root/
         HOME=/tmp
         /nix/var/nix/profiles/default/bin/nix-env -i ${self.envCommand} --option sandbox false
      '')
    );

  ## At installation time, select the profile for the target system as
  ## the actual profile and remove all other platform profiles. Also
  ## install the SDE environment if withSdeEnv is enabld.
  postRootFsInstallCmds = lib.singleton (callPackage ./post-install-cmd.nix { inherit nixProfile activate; });

  platformProperties = import ../../../bf-platforms/properties.nix;
  mkGrubDefault = platform:
    let
      properties =
        assert lib.assertMsg (hasAttr platform platformProperties) ''Unsupported platform "${platform}"'';
        platformProperties.${platform};
    in {
      ${platform} = builtins.toFile "grub-default-${platform}" ''
        GRUB_DEFAULT=0
        GRUB_TIMEOUT=5
        GRUB_CMDLINE_LINUX_DEFAULT="console=${properties.serialDevice},${properties.serialSettings}"
        GRUB_CMDLINE_LINUX=""
        GRUB_TERMINAL="console"
      '';
    };
  grubDefault = builtins.foldl' (final: next: final // mkGrubDefault next) {} platforms';

  ## Add platform-dependent udev rules to the file tree
  addUdevRule = platform:
    let
      pciAddr = platformProperties.${platform}.mgmtEthPciAddr or null;
    in
      if pciAddr != null then
        ''
          if [ -d $out/__platforms ]; then
             chmod -R a+w $out/__platforms
          fi
          dir=$out/__platforms/${platform}/etc/udev/rules.d
          mkdir -p $dir
          echo 'ACTION=="add", SUBSYSTEM=="net", KERNELS=="${pciAddr}", NAME="mgmt0"' >$dir/20-mgmt0.rules
        ''
      else
        "";
  fileTree' = runCommand "file-tree-udev-rules" {} (''
    mkdir $out
    cp -r ${fileTree}/* $out
  '' +
  (with builtins; concatStringsSep "\n" (
    map addUdevRule platforms'
  )));
in assert lib.assertMsg (platforms' != []) "No platforms selected (note that the Tofino model is not supported)";
  trace "Building for platforms ${concatStringsSep ", " platforms'}"
    lib.makeOverridable mkOnieInstaller {
      inherit version rootPaths users postRootFsCreateCmds postRootFsInstallCmds
        component NOS grubDefault bootstrapProfile binaryCaches;
      fileTree = fileTree';
      ## Prevent accidental upgrades of the kernel. Kernel upgrades have
      ## to be coordinated with an upgrade of the NOS to provide matching
      ## kernel modules.
      holdPackages = [ "linux-image-amd64" ];
    }
