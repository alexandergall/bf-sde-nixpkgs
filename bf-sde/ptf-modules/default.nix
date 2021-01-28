{ pname, version, src, patches, stdenv, python2, makeWrapper, bf-drivers }:


python2.pkgs.buildPythonApplication rec {
  inherit pname version src patches;

  ## This pulls in the propagated build inputs from bf-drivers
  ## (i.e. grpcio, tenjin, setuptools)
  propagatedBuildInputs = [
    bf-drivers
  ] ++
  ## Other runtime dependencies of ptf-modules and ptf-utils. This is
  ## most likely not complete yet.
  (with python2.pkgs; [ scapy thrift ]);

  catchConflicts = false;
  preConfigure = ''pushd ptf'';

  ## ptf-utils imports the bfrt_grpc modules provided by bf-drivers
  postInstall = ''
    wrapProgram "$out/bin/ptf" --prefix PYTHONPATH : "${bf-drivers}/lib/python2.7/site-packages/tofino"
  '';
}
