{ lib, stdenv, fetchFromGitHub, makeWrapper, coreutils, kmod,
  i2c-tools, gnugrep, ... }:

stdenv.mkDerivation {
  name = "netberg-i2c-utils";
  src = fetchFromGitHub {
    owner  = "netbergtw";
    repo   = "files";
    rev    = "6062440";
    sha256 = "1m3mbmjqwarrgggj4xc60smabk0fv7qgzw2z7y7spizg5vv0chx5";
  };
  buildInputs = [ makeWrapper ];
  patches = ./i2c_utils.patch;
  installPhase = ''
    mkdir -p $out/bin
    cp debian-bsps/aurora-710/i2c_utils.sh $out/bin
    wrapProgram $out/bin/i2c_utils.sh \
      --set PATH "${lib.strings.makeBinPath [ coreutils kmod i2c-tools gnugrep ]}"
  '';
}
