{ pname, version, src, patches, lib, stdenv, bf-drivers, makeWrapper,
  bridge-utils, inetutils }:

let
  python = bf-drivers.pythonModule;
in stdenv.mkDerivation rec {
  inherit pname version src patches;

  buildInputs = [ python python.pkgs.wrapPython makeWrapper ];

  preConfigure = ''
    cd ptf-utils
  '' + lib.optionalString (version == "9.1.1") ''
    sed -i Makefile.in -e '/^ixia_utils.*$/d'
  '';

  preBuild = ''
    substituteInPlace run_ptf_tests.py --replace six.print '#six.print'
  '';
  postInstall = ''
    utilsPath=$out/lib/${python.libPrefix}/site-packages/p4testutils/
    chmod a+x $utilsPath/run_ptf_tests.py $utilsPath/bf_switchd_dev_status.py
    for program in $out/bin/port_*; do
      wrapProgram $program --prefix PATH : "${lib.strings.makeBinPath [ bridge-utils inetutils ]}"
    done

    ## The veth_{setup,teardown}.sh scripts are provided by
    ## the tools package
    rm -f $out/bin/veth*
  '';

  pythonPath = with python.pkgs; [ six ];
  postFixup = ''
    wrapPythonProgramsIn $utilsPath "$utilsPath $pythonPath"
  '';
}

