{ lib, runCommand, closureInfo, coreutils, gnutar, gnused, gawk, xz,
  rsync, ncurses }:

{ release, version, gitTag, nixProfile, component }:

let
  sliceInfo = slice:
    let
      rootPaths = builtins.attrValues slice;
      closure = closureInfo { inherit rootPaths; };
    in builtins.concatStringsSep ":" (
      [ slice.sliceFile closure ] ++ rootPaths);
  sliceInfos = builtins.map sliceInfo (builtins.attrValues release);
  ID = "${version}:${gitTag}";
in runCommand "${component}-standalone-installer" {
  inherit sliceInfos;
} ''
  mkdir tmp
  cd tmp
  storePaths=
  for info in $sliceInfos; do
    read sliceFile closureInfo rootPaths < <(echo $info | tr ':' ' ')
    read kernelID kernelRelease platform < <(cat $sliceFile/slice | tr ':' ' ')
    dest=$kernelRelease/$kernelID/$platform
    mkdir -p $dest
    cp $closureInfo/{registration,store-paths} $dest
    storePaths="$storePaths $closureInfo/store-paths"
    echo "$rootPaths" >$dest/rootPaths
  done

  tar cf store-paths.tar $(cat $storePaths | sort | uniq | tr '\n' ' ')
  echo "${ID}" >version
  echo ${nixProfile} >profile
  substitute ${./install.sh} install.sh \
    --subst-var-by COMPONENT ${component}
  chmod a+x install.sh
  patchShebangs install.sh

  tar cf ../archive.tar *
  cd ..
  xz -T0 archive.tar

  mkdir $out
  ## PATH includes the paths required by install.sh and is exported by
  ## the self-extractor. This is necessary for Nix to find the paths
  ## when scanning for runtime dependencies as install.sh is
  ## compressed.
  substitute ${./self-extractor.sh} $out/installer.sh --subst-var-by PATH \
    "${lib.strings.makeBinPath [ coreutils gnutar gawk xz gnused rsync ncurses ]}"
  cat archive.tar.xz >>$out/installer.sh
  chmod a+x $out/installer.sh
  patchShebangs $out/installer.sh
  ## For the Hydra post-build hook
  echo ${ID} >$out/version
  echo "${component}" >$out/component
''
