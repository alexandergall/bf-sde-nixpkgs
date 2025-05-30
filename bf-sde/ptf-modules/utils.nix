{ runtime ? false, pname, version, buildSupport, src, patches, lib,
  stdenv, bf-drivers, makeWrapper, bridge-utils, inetutils, gnugrep,
  coreutils, utillinux, ethtool, iproute2, procps, jq, cmake, thrift
  }:

let
  python = bf-drivers.pythonModule;
in stdenv.mkDerivation {
  pname = "ptf-utils" + lib.optionalString runtime "-runtime";
  inherit version patches;
  src = buildSupport.fixupSrc {
    inherit src;
    cmakeRules = ''
      add_subdirectory(ptf-utils)
    '';
  };

  nativeBuildInputs = [ cmake python.pkgs.wrapPython makeWrapper thrift ];
  buildInputs = [ python ];

  cmakeFlags = [
    "-DSTANDALONE=ON"
  ];

  postInstall = ''
    utilsPath=$out/lib/${python.libPrefix}/site-packages/p4testutils/
    chmod a+x $utilsPath/*
  '' + (lib.optionalString runtime ''
    rm -rf $out/share $utilsPath/*
  '') + ''
    for program in $out/bin/port_*; do
      wrapProgram $program \
        --set PATH "${lib.strings.makeBinPath [ bridge-utils inetutils gnugrep ]}"
    done

    ## Some of the python utilities are not compatible with
    ## Python3. The canonical build doesn't notice because it doesn't
    ## compile them during installation, but we do. Since nobody appears
    ## to have noticed, chances are that they are not used anywhere.
    rm -f $utilsPath/{traffic_streams.py,traffic_utils.py}

    python -m compileall $utilsPath
    mv $out/bin/veth_setup.sh $out/bin/veth_setup_orig.sh
    substituteInPlace $out/bin/veth_setup_orig.sh --replace /sbin/ethtool ethtool
    wrapProgram $out/bin/veth_setup_orig.sh \
      --set PATH "${lib.strings.makeBinPath [ coreutils ethtool iproute2 gnugrep procps ]}"
    mv $out/bin/veth_teardown.sh $out/bin/veth_teardown_orig.sh
    wrapProgram $out/bin/veth_teardown_orig.sh \
      --set PATH "${lib.strings.makeBinPath [ coreutils iproute2 ]}"
    cp ${./veth_from_portinfo} $out/bin/veth_from_portinfo
    wrapProgram $out/bin/veth_from_portinfo \
      --set PATH "${lib.strings.makeBinPath [ coreutils utillinux ethtool iproute2 gnugrep procps jq ]}"
    substitute ${./veth_setup.sh} $out/bin/veth_setup.sh \
      --subst-var-by PTF_UTILS $out
    chmod a+x $out/bin/veth_setup.sh
    substitute ${./veth_teardown.sh} $out/bin/veth_teardown.sh \
      --subst-var-by PTF_UTILS $out
    chmod a+x $out/bin/veth_teardown.sh
  '';

  pythonPath = with python.pkgs; [ six ];
  postFixup = ''
    wrapPythonProgramsIn $utilsPath "$utilsPath $pythonPath"
  '';
}

