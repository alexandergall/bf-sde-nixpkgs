{ stdenv, src, version, lib, makeWrapper, python2, ethtool, iproute }:

stdenv.mkDerivation {
  inherit version src;
  name = "bf-tools-${version}";

  buildInputs = [ python2 makeWrapper ethtool iproute ];
  patches = [ ./run_switchd.patch ./run_p4_tests.patch ];

  installPhase = ''
    mkdir -p $out/bin

    ## These scripts were copied from the tools provided for
    ## the BF Academy courses.
    cp ${./p4_build.sh} $out/bin/p4_build.sh
    cp ${./veth_setup.sh} $out/bin/veth_setup.sh
    cp ${./veth_teardown.sh} $out/bin/veth_teardown.sh
    for program in $out/bin/veth*; do
      substituteInPlace $program --replace /sbin/ethtool ethtool
      wrapProgram $program --prefix PATH : "${lib.strings.makeBinPath [ ethtool iproute ]}"
    done

    cp *manifest $out
    cp run_switchd.sh $out/bin
    cp run_tofino_model.sh $out/bin

    ## A test script could need additional Python modules at runtime.
    ## The bare ptf command has an option --pypath for this purpose,
    ## but it is hidden behind the run_p4_test.sh wrapper. We could
    ## simply set PYTHONPATH directly before running run_p4_test.sh,
    ## but this could interfere with other Python programs run in the
    ## same environment.  To isolate the additional modules, we use
    ## PTF_PYTHONPATH and translate it to PYTHONPATH in the wrapper.
    cp run_p4_tests.sh $out/bin
    wrapProgram $out/bin/run_p4_tests.sh --run "export PYTHONPATH=\$PTF_PYTHONPATH:\$PYTHONPATH"

    mkdir -p $out/pkgsrc/p4-build
    tar -C $out/pkgsrc/p4-build -xf packages/p4-build* --strip-component 1
    chmod a+x $out/pkgsrc/p4-build/tools/*

    mkdir -p $out/pkgsrc/p4-examples
    tar -C $out/pkgsrc/p4-examples -xf packages/p4-examples* --wildcards "p4-examples*/tofino*" --strip-components 1
  '';
}
