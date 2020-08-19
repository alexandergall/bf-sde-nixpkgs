let
  pkgs = import ../../nixpkgs.nix;
in with pkgs;
stdenv.mkDerivation rec {
  name = "bf-sde-environment";
  buildInputs = [ bf-sde getopt which sysctl utillinux ];
	      
  shellHook = ''
    set -e

    if [ -z "$SDE" -o -z "$SDE_INSTALL" ]; then
      echo "SDE or SDE_INSTALL not set"
      exit 1
    fi

    echo "Changing working directory to $SDE"
    cd $SDE

    storePath=${bf-sde}
    if [ ! -h .store_path -o "$(readlink .store_path)" != "$storePath" ]; then
      echo "Creating initial copy of SDE"
      (cd $storePath && tar cf - .) | tar xf -
      chmod u+w $SDE
      chmod u+w $SDE_INSTALL/share/p4/targets/tofino
      chmod u+w $SDE_INSTALL/share/tofinopd
      ln -s $storePath .store_path
    fi

    PATH=$PATH:$SDE_INSTALL/bin:$SDE

    ## Make sudo available through PATH
    . /etc/os-release
    if [ $ID == "nixos" ]; then
      PATH=$PATH:/run/wrappers/bin
    else
      PATH=$PATH:/usr/bin
    fi
    sudo mkdir -p /mnt
    set +e
  '';
}
