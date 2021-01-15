## Generic part of the builder for a kernel build tree.  It only
## provides the patching of ELF binaries in the installPhase.  The
## caller must override the unpackPhase to provide the actual build
## tree in $out

{ stdenv, autoPatchelfHook, patchelfInputs }:

stdenv.mkDerivation {
  buildInputs = [ autoPatchelfHook ] ++ patchelfInputs;

  unpackPhase = ''
    echo "Please override unpackPhase"
    exit 1;
  '';

  dontInstall = true;
}
