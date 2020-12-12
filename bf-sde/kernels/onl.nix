{ deb, mkKbuild }:

mkKbuild.overrideAttrs (_: {
  name = "onl-kbuild";
  unpackPhase = ''
    mkdir $out
    ar x ${deb}
    tar -C $out -xf data.tar.* ./usr/share/onl --strip-components 8
  '';
})
