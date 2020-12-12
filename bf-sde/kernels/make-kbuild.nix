## Generic part of the builder for a kernel build tree.  It only
## provides the patching of ELF binaries in the installPhase.  The
## caller must override the unpackPhase to provide the actual build
## tree in $out

{ stdenv, lib, binutils-unwrapped, glibc,
  findutils, file, openssl_1_1, openssl_1_0_2, libelf, elfutils }:

stdenv.mkDerivation {
  unpackPhase = ''
    echo "Please override unpackPhase"
    exit 1;
  '';

  installPhase = ''
    set -e

    PATH=$PATH:${lib.makeBinPath [ binutils-unwrapped findutils file ]}

    function addPath () {
      path=$1
      obj=$2
      if ! [ -f $path/$obj ]; then
        echo "Object $obj not present in $path"
        exit 1
      fi
      echo "Adding RPATH $path for $obj"
      paths[$path]=1
    }

    echo "Fixing up binaries"
    for dirs in $out/scripts $out/tools; do
      for f in $(find $dirs -type f); do
        read type arch rest <<<$(file -b $f)
        [ "$type" == "ELF" ] || continue
        [[ "$rest" =~ "dynamically linked" ]] || continue
        if [ "$arch" != "64-bit" ]; then
          echo "Skipping $f ELF/$arch"
          continue
        fi

        echo "Patching $type/$arch $f"
        chmod a+w $f
        patchelf --set-interpreter ${glibc}/lib/ld-linux* $f || true

        unset paths
        declare -A paths
        for path in $(patchelf --print-rpath $f); do
          paths[$path]=1
        done

        for lib in $(patchelf --print-needed $f); do
          match=
          case ''${match:=$lib} in
            libc.so.6)
              addPath ${glibc}/lib $match
              ;;
            libcrypto.so.1.1)
              addPath ${openssl_1_1.out}/lib $match
              ;;
            libcrypto.so.1.0.0)
              addPath ${openssl_1_0_2.out}/lib $match
              ;;
            libelf.so.0)
              addPath ${libelf}/lib $match
              ;;
            libelf.so.1)
              addPath ${elfutils}/lib $match
              ;;
            *)
              echo "Unhandled object $lib in $f"
              exit 1
              ;;
          esac
        done
        patchelf --set-rpath $(echo ''${!paths[@]} | tr ' ' ':') $f
      done
    done
  '';
}
