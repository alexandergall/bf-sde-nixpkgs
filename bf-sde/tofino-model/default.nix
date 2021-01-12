{ pname, version, patches, src, stdenv, autoPatchelfHook, libcli }:

let
  arch = if stdenv.isx86_64
    then
      "x86_64"
    else if stdenv.isi686
      then
        "i686"
      else
        throw "Unsupported architecture";
in stdenv.mkDerivation {
  inherit pname version src;

  buildInputs = [ autoPatchelfHook libcli ];

  installPhase = ''
    mkdir -p $out/bin
    cp tofino-model.${arch}.bin $out/bin/tofino-model
  '';
}
