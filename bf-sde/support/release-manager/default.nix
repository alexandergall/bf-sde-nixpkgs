{ stdenv, lib, coreutils, utillinux, gnused, gawk, jq, curl, systemd,
  gnutar, gzip, git, kmod, ncurses, findutils }:

{ version, nixProfile, repoUrl, apiUrl, apiType,
  activationCode, installCmds ? "" }:

assert lib.asserts.assertOneOf "API Type" apiType [ "github" "bitbucket" ];

let
  gitApi = {
    github = ./github_api.sh;
    bitbucket = ./bitbucket_api.sh;
  }.${apiType};
in stdenv.mkDerivation {
  pname = "release-manager";
  inherit version;
  phases = [ "installPhase" ];
  installPhase = ''
    mkdir -p $out/bin
    substitute ${./release-manager} $out/bin/release-manager \
      --subst-var-by PATH \
        "${lib.strings.makeBinPath [ coreutils utillinux gnused gawk
                                     jq curl systemd gnutar gzip git kmod ncurses
                                     findutils ]}" \
      --subst-var-by PROFILE ${nixProfile} \
      --subst-var-by API_URL ${apiUrl} \
      --subst-var-by REPO_URL ${repoUrl} \
      --subst-var-by SELF $out
    chmod a+x $out/bin/*
    patchShebangs $out/bin

    mkdir -p $out/lib
    cp ${gitApi} $out/lib/api.sh
    cp ${activationCode} $out/lib/activation.sh
  '' + installCmds;
}
