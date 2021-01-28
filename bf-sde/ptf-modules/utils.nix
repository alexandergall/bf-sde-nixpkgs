{ pname, version, src, patches, lib, stdenv, python2, makeWrapper,
  bridge-utils, inetutils }:

stdenv.mkDerivation rec {
  inherit pname version src patches;

  buildInputs = [ python2 makeWrapper ];

  preConfigure = ''
    cd ptf-utils
  '' + lib.optionalString (version == "9.1.1") ''
    sed -i Makefile.in -e '/^ixia_utils.*$/d'
  '';

  preBuild = ''
    substituteInPlace run_ptf_tests.py --replace six.print '#six.print'
  '';
  postInstall = ''
    chmod a+x $out/lib/python*/site-packages/p4testutils/run_ptf_tests.py
    for program in $out/bin/port_*; do
      wrapProgram $program --prefix PATH : "${lib.strings.makeBinPath [ bridge-utils inetutils ]}"
    done

    ## The veth_{setup,teardown}.sh scripts are provided by
    ## the tools package
    rm -f $out/bin/veth*
  '';

}

