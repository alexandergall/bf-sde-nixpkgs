#!/bin/bash

## This also contains the PATH for ./install.sh
export PATH=@PATH@

cleanup () {
    chmod -R a+w $TMPDIR
    rm -rf $TMPDIR
}
export TMPDIR=$(mktemp -d /var/tmp/selfextract.XXXXXX)
trap cleanup EXIT TERM INT
archive=$(awk '/^___ARCHIVE_BELOW___/ {print NR + 1; exit 0; }' $0)
echo "Unpacking archive"
tail -n+$archive $0 | tar xJ -C $TMPDIR
cwd=$(pwd)
cd $TMPDIR
./install.sh
cd $cwd
exit 0
___ARCHIVE_BELOW___
