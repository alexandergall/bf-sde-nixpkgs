{ version, stdenv, lib, coreutils, gnused, utillinux, nix,
  runCommand, git }:

let
  isDirty = import (runCommand "check-dirty" {} ''
    cd ${../../..}
    if [ -z "$(${git}/bin/git status --porcelain)" ]; then
      echo false >$out
    else
      echo true >$out
    fi
  '');
  filter = path: type:
    let
      basename = baseNameOf path;
    in
      with builtins;
      ! (basename == ".git" ||
         basename == "Makefile" ||
         match "result.*" basename != null ||
         match ".*~" basename != null);
  src =
    assert lib.assertMsg (! isDirty) "This build must be run from a clean Git repository";
    builtins.filterSource filter ../../..;
in stdenv.mkDerivation {
  pname = "sde-env";
  inherit version src;
  phases = [ "installPhase" "fixupPhase" ];
  installPhase = ''
    mkdir -p $out/bin
    cmd=$out/bin/sde-env-${version}
    export VERSION=${version}
    substitute ${./sde-env.sh} $cmd \
      --subst-var-by PATH ${lib.strings.makeBinPath [ coreutils gnused utillinux nix ]} \
      --subst-var-by SDE_NIXEXPR ${src} \
      --subst-var VERSION
    chmod a+x $cmd
  '';
}
