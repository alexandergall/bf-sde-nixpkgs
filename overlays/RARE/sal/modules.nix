{ python2 }:

python2.pkgs.buildPythonPackage rec {
  pname = "sal-bf2556-t1";
  version = "20.6.23";

  src = /home/gall/rare-bf2556x-1t;

  preConfigure = ''
    cd modules
  '';
}
