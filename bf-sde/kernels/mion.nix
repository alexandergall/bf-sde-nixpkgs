{ version, localVersion, kbuild, mkKbuild }:

mkKbuild.overrideAttrs (_: {
  name = "mion-kbuild";
  unpackPhase = ''
    mkdir $out
    tar -C ${kbuild} -cf - lib/modules/${version}${localVersion}/build | \
      tar -C $out -xf - --strip-components 4
  '';
})
