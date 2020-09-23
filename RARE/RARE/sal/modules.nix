{ fetchBitbucketPrivate, python2 }:

let
  repo = import ./repo.nix { inherit fetchBitbucketPrivate; };
in python2.pkgs.buildPythonPackage rec {
  pname = "sal-bf2556-t1";
  inherit (repo) version src;

  preConfigure = ''
    cd modules
  '';
}
