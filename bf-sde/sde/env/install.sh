#!/bin/bash
set -e

NIX_PATH=

if nix-env -q --installed | grep sde-env-@VERSION@ >/dev/null; then
    echo "Version @VERSION@ is already installed"
    echo "To replace, first remove the existing command with \"nix-env -e sde-env\" (as root)"
    echo "then execute the installer again".
    exit 0
fi

echo "Unpacking paths"
tar xf store-paths.tar*

echo "Copying paths to Nix store"
cleanup () {
    chmod -R a+w $TMPDIR
    rm -rf $TMPDIR
}
TMPDIR=$(mktemp -d /var/tmp/nix.XXXXXX)
trap cleanup EXIT TERM INT
mount --bind /nix/store $TMPDIR
mount -o remount,rw $TMPDIR
for path in $(cat ./store-paths); do
    path=$(echo $path | sed -e 's,^/,,')
    echo $path
    rsync -a $path $TMPDIR
done
umount $TMPDIR

echo "Registering paths in DB"
cat ./registration | nix-store --load-db

echo "Installing sde-env command"
nix-env -i $(cat sde-env-path) --preserve-installed
