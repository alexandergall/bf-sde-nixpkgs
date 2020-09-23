{ bf-sde, fetchgit, sal_modules, python2, makeWrapper }:

let
  repo = import ./repo.nix { inherit fetchgit; };
in python2.pkgs.buildPythonApplication rec {
  inherit (repo) version src;
  pname = "bf_forwarder";

  propagatedBuildInputs = [
    bf-sde sal_modules
    (python2.withPackages (ps: with ps; [ ]))
  ];
  buildInputs = [ makeWrapper ];

  preConfigure = ''
    cd bfrt_python
  '';

  postInstall = ''
    wrapProgram "$out/bin/bf_forwarder.py" --set PYTHONPATH "${bf-sde}/install/lib/python2.7/site-packages/tofino"
  '';
}
