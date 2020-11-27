{ deb, stdenv, lib, runCommand, binutils-unwrapped, glibc,
  findutils, file, openssl, elfutils }:

runCommand "onl-kbuild" {}
  ''
    set -e

    PATH=$PATH:${lib.makeBinPath [ binutils-unwrapped findutils file ]}

    mkdir $out
    ar x ${deb}
    tar -C $out -xf data.tar.* ./usr/share/onl --strip-components 8

    echo "Fixing up binaries"
    for dirs in $out/scripts $out/tools; do
      for f in $(find $dirs -type f); do
        if file -b $f | grep ELF >/dev/null; then
          echo $f
          patchelf --set-interpreter ${glibc}/lib/ld-linux* $f || true
          rpath=
          for lib in $(patchelf --print-needed $f); do
            case $lib in
              libc.so.6)
                rpath=$rpath:${glibc}/lib
                ;;
              libcrypto.so.1.1)
                rpath=$rpath:${openssl}/lib
                ;;
              libelf.so.1)
                rpath=$rpath:${elfutils}/lib
              ;;
              *)
                echo "Unhandled object $lib in $f"
                exit 1
                ;;
            esac
          done
          patchelf --set-rpath ''${rpath/#:/} $f
        fi
      done
    done
  ''
