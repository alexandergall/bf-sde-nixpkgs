{ pname, version, src, patches, stdenv, python3, autoPatchelfHook, zlib }:

let
  python3Env = python3.withPackages (ps: with ps;
    [ packaging jsonschema jsl ]);
in stdenv.mkDerivation {
  inherit pname version src patches;

  propagatedBuildInputs = [ python3Env ];
  buildInputs = [ autoPatchelfHook zlib ];

  installPhase = ''
    mkdir $out
    tar -C $out -xf p4c* --strip-components 1

    ## Versions prior to 9.3.0 installed p4c as a copy of bf-p4c
    if ! [ -e $out/bin/p4c ]; then
      ln -sr $out/bin/bf-p4c $out/bin/p4c
    fi
  '';
}
