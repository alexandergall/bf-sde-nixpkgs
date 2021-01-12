{ stdenv, src, version }:

stdenv.mkDerivation {
  inherit version src;
  name = "bf-tools-${version}";

  patches = [ ./run_switchd.patch ];

  installPhase = ''
    mkdir -p $out/bin

    ## These scripts were copied from the tools provided for
    ## the BF Academy courses.
    cp ${./p4_build.sh} $out/bin/p4_build.sh
    cp ${./veth_setup.sh} $out/bin/veth_setup.sh
    cp ${./veth_teardown.sh} $out/bin/veth_teardown.sh

    cp run_switchd.sh $out/bin
    cp run_tofino_model.sh $out/bin
    cp *manifest $out

    mkdir -p $out/pkgsrc/p4-build
    tar -C $out/pkgsrc/p4-build -xf packages/p4-build* --strip-component 1

    mkdir -p $out/pkgsrc/p4-examples
    tar -C $out/pkgsrc/p4-examples -xf packages/p4-examples* --wildcards "p4-examples*/tofino*" --strip-components 1
  '';
}
