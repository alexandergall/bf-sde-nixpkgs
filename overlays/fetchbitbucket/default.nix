## Bitbucket currently doesn't support deployment tokens
## like GitHub or GitLab.  Instead, one needs to use a
## SSH key pair for private access (called "Access key").
## This function is an adaptation of the regular fetchgitPrivate
## function which takes a private SSH key file as input.  The
## key's passphrase must be empty.
{ fetchgit, runCommand, makeWrapper, openssh,
  identityFile }: args: derivation ((fetchgit args).drvAttrs // {

  GIT_SSH = let
    ssh-wrapped = runCommand "fetchgit-ssh" {
      nativeBuildInputs = [ makeWrapper ];
    } ''
      mkdir -p $out/bin
      makeWrapper ${openssh}/bin/ssh $out/bin/ssh --prefix PATH : "$out/bin" --add-flags \
        "-o StrictHostKeyChecking=no -i ${identityFile}" "$@"
    '';
  in "${ssh-wrapped}/bin/ssh";
})
