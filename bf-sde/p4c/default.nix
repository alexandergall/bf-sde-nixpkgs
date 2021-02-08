{ pname, version, src, patches, stdenv, python3, autoPatchelfHook, zlib }:

stdenv.mkDerivation {
  inherit pname version src patches;

  buildInputs = [ autoPatchelfHook zlib python3.pkgs.wrapPython ];

  installPhase = ''
    mkdir $out
    tar -C $out -xf p4c* --strip-components 1

    ## Versions prior to 9.3.0 installed p4c as a copy of bf-p4c
    if ! [ -e $out/bin/p4c ]; then
      ln -sr $out/bin/bf-p4c $out/bin/p4c
    fi
  '';

  pythonPath = with python3.pkgs; [ packaging jsonschema jsl ];
  postFixup = ''
    wrapPythonPrograms
  '';
}
