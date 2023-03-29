## Build a "standalone" installer for the sde-env-* command.  It is
## designed to be self-contained, i.e. it contains the closure of the
## command for all possible platforms and kernels. It can be used to
## install the SDE on a system that does not have access to a binary
## cache.

{ bf-sde, nixpkgsSrc, lib, closureInfo, runCommand,
  coreutils, gnutar, gawk, gnugrep, gnused, xz, rsync,
  utillinux, nix, bashInteractive }:

let
  mkEnvInputDrv = { kernelID, platform }:
    (bf-sde.mkShell {
      inherit kernelID platform;
    }).inputDerivation;
  rootPaths =
    with builtins;
    let
      kernelID = attrNames bf-sde.pkgs.kernel-modules;
      platform = attrNames bf-sde.platforms;
    in
      map mkEnvInputDrv
        (lib.cartesianProductOfSets { inherit kernelID platform; });
  closure = closureInfo {
    rootPaths =
      ## List of input derivations of mkShell for all platforms and
      ## kernels.
      rootPaths
      ## envCommand contains a copy of the bf-sde-nixpkgs Git
      ## repository, but not the nixpkgs expression pinned in the
      ## top-level default.nix. To be self-contained, we must include
      ## a copy of that as well, provided by nixpkgsSrc.
      ++ [ bf-sde.envCommand nixpkgsSrc ]
      ## nix-shell via envCommand also requires the man, doc, info and
      ## dev outputs of bashInteractive when it is run. These
      ## dependencies are not part of the mkShell inputDerivation.  We
      ## add them here explicitly until we figure out how to do this
      ## properly.
      ++ (with bashInteractive; [ doc info man dev ])
      ## Build dependencies for the "unsupported-kernel" package.
      ++ [ (bf-sde.modulesForKernel "none").inputDerivation ];
  };
in runCommand "sde-env-${bf-sde.version}-standalone-installer" {} ''
  mkdir tmp
  cd tmp

  echo "Creating archive of store paths... ${closure}"
  tar cf store-paths.tar $(cat ${closure}/store-paths)

  cp ${closure}/{registration,store-paths} .
  echo ${bf-sde.envCommand} >sde-env-path
  substitute ${./install.sh} install.sh --subst-var-by VERSION ${bf-sde.version}
  chmod a+x install.sh
  patchShebangs install.sh
  tar cf payload.tar store-paths.tar registration \
    store-paths sde-env-path install.sh
  rm store-paths.tar

  echo "Compressing payload..."
  xz -T0 payload.tar

  mkdir $out
  substitute ${../../support/installers/standalone/self-extractor.sh} $out/installer.sh --subst-var-by PATH \
    "${lib.strings.makeBinPath [ coreutils gnutar gawk gnugrep xz gnused rsync utillinux nix ]}"
  chmod a+w $out/installer.sh
  cat payload.tar.xz >>$out/installer.sh
  chmod a+x $out/installer.sh
  patchShebangs $out/installer.sh
''
