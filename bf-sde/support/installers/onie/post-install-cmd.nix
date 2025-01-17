{ lib, writeShellScript, nixProfile, activate }:

writeShellScript "post-install-cmd" (''
  set -e
  red="\033[01;31m"
  green="\033[01;32m"
  normal="\033[0m"
  . /etc/machine.conf
'' + lib.optionalString (nixProfile != null) ''
  profiles=(${nixProfile}*)
  if [ "''${profiles[0]}" != '${nixProfile}*' ]; then
    target=${nixProfile}-$onie_machine
    if [ -d "$target" ]; then
      echo -e "''${green}Installing profile ${nixProfile} for platform $onie_machine''${normal}"
      (cd $target && mv * ..)
      rm -rf ''${profiles[@]}
      if [ -n "${builtins.toString activate}" ]; then
        echo -e "''${green}Activating service''${normal}"
        ${nixProfile}/bin/release-manager --activate-current
      fi
    else
      echo -e "''${red}Unsupported platform: $onie_machine"
      echo -e "${nixProfile} cannot be activated''${normal}"
    fi
  fi
'' + ''
  if [ -d /nix/var/nix/gcroots/per-user/root/sde-env ]; then
    if [ -e /nix/var/nix/gcroots/per-user/root/sde-env/$onie_machine.tmp ]; then
      echo -e "''${green}Setting Nix garbage collection root for SDE development environment on platform $onie_machine''${normal}"
      mv /nix/var/nix/gcroots/per-user/root/sde-env/$onie_machine.tmp /nix/var/nix/gcroots/per-user/root/sde-env/$onie_machine
      rm -f /nix/var/nix/gcroots/per-user/root/sde-env/*.tmp
    else
      echo -e "''${red}Unsupported platform: $onie_machine"
      echo -e "SDE development environment not available''${normal}"
    fi
  fi
  echo -e "''${green}Cleaning up Nix store''${normal}"
  /nix/var/nix/profiles/default/bin/nix-collect-garbage
'')
