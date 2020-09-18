{ bf-sde, sal_modules, python2, makeWrapper }:

python2.pkgs.buildPythonApplication rec {
  pname = "bf_forwarder";
  version = "20.6.23";

  src = /home/gall/rare;

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
