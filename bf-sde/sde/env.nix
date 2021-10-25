{ runCommand, git, gnumake }:

let
  sdeNixexpr = ../../.;
in runCommand "sde-env" {} ''
  set -x
  ${git}/bin/git ls-files ${./.}
  mkdir -p $out/bin
  cat <<EOF >$out/bin/sde-env
  #!/bin/bash
  cd ${sdeNixexpr}
  ${gnumake}/bin/make env
  EOF
  chmod a+x $out/bin/sde-env
''
