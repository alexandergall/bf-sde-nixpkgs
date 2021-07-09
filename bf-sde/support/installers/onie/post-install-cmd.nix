{ writeShellScript, nixProfile }:

writeShellScript "post-install-cmd" ''
  set -e
  . /etc/machine.conf
  profiles=(${nixProfile}*)
  [ "''${profiles[0]}" == '${nixProfile}*' ] && exit 0
  target=${nixProfile}-$onie_machine
  if [ -d $target ]; then
    echo -en "\033[01;32m"
    echo -n "Activating ${nixProfile} for platform $onie_machine"
    echo -e "\033[0m"
    (cd $target && mv * ..)
    rm -rf ''${profiles[@]}
    ${nixProfile}/bin/release-manager --activate-current

    echo "Cleaning up Nix store"
    /nix/var/nix/profiles/default/bin/nix-collect-garbage
  else
    echo -en "\033[01;31m"
    echo "Unsupported platform: $onie_machine"
    echo "${nixProfile} cannot be activated"
    echo -e "\033[0m"
  fi
''
