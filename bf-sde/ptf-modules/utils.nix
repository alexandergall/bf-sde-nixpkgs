{ runtime ? false, pname, version, src, patches, lib, stdenv,
  bf-drivers, makeWrapper, bridge-utils, inetutils, gnugrep,
  coreutils, ethtool, iproute, procps }:

let
  python = bf-drivers.pythonModule;
in stdenv.mkDerivation rec {
  pname = "ptf-utils" + lib.optionalString runtime "-runtime";
  inherit version src patches;

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
  '' +
  (if runtime
   then
     ''
       mv $utilsPath/bf_switchd_dev_status.py $TEMP
       rm -rf $out/bin $out/share $utilsPath/*
       mv $TEMP/bf_switchd_dev_status.py $utilsPath
     ''
   else
     ''
        for program in $out/bin/port_*; do
          wrapProgram $program \
            --set PATH "${lib.strings.makeBinPath [ bridge-utils inetutils gnugrep ]}"
        done

        substitute veth_setup.sh $out/bin/veth_setup.sh --replace /sbin/ethtool ethtool
        wrapProgram $out/bin/veth_setup.sh \
          --set PATH "${lib.strings.makeBinPath [ coreutils ethtool iproute gnugrep procps ]}"
        cp veth_teardown.sh $out/bin
        wrapProgram $out/bin/veth_teardown.sh \
          --set PATH "${lib.strings.makeBinPath [ coreutils iproute ]}"
      '');

  pythonPath = with python.pkgs; [ six ];
  postFixup = ''
    wrapPythonProgramsIn $utilsPath "$utilsPath $pythonPath"
  '';
}

