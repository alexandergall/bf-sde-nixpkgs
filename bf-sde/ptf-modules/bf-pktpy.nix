{ pname, version, src, patches, bf-drivers }:

let
  python = bf-drivers.pythonModule;
in python.pkgs.buildPythonPackage rec {
  pname = "bf-pktpy";
  inherit version src patches;

  propagatedBuildInputs = with python.pkgs;
    [ ipaddress six netifaces psutil ];
  preConfigure = ''pushd bf-pktpy'';
}
