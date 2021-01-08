{ mkKbuild, fetchgit, source, kbuild }:

mkKbuild.overrideAttrs (_: {
  name = "mion-kbuild";
  unpackPhase = ''
    mkdir $out
    tar -C $out -xf ${kbuild} --strip-components 1
    rm -f $out/source
    mkdir $out/source
    tar -C $out/source -xf ${source} --strip-components 1
    echo "include source/Makefile" >$out/Makefile
  '';
})
