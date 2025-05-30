{ version, stdenv, lib, coreutils, gnused, utillinux, nix,
  runCommand, git, withAsic }:

let
  ## Note: copy the Git repo to avoid the "unsafe repository" problem
  isDirty = import (runCommand "check-dirty" {} ''
    tmp=$(mktemp -d)
    tar -C ${../../..} -cf - . | tar -C $tmp -xf -
    if [ -z "$(${git}/bin/git -C $tmp status --porcelain)" ]; then
      echo false >$out
    else
      echo true >$out
    fi
    chmod -R u+w $tmp
    rm -rf $tmp
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
    export WITH_ASIC=${lib.boolToString withAsic}
    substitute ${./sde-env.sh} $cmd \
      --subst-var-by PATH ${lib.strings.makeBinPath [ coreutils gnused utillinux nix ]} \
      --subst-var-by SDE_NIXEXPR ${src} \
      --subst-var VERSION \
      --subst-var WITH_ASIC
    chmod a+x $cmd
  '';
}
