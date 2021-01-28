{ pname, version, src, patches, python2 }:

python2.pkgs.buildPythonPackage rec {
  inherit pname version src patches;

  buildInputs = with python2.pkgs; [ ply ];
  preConfigure = ''
    substituteInPlace setup.py --replace "if self.root is not None:" "if False:"
  '';
}


