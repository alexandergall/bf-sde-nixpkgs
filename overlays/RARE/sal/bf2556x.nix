{ python2, sal_modules, fetchBitbucketPrivate }:

let
  repo = import ./repo.nix { inherit fetchBitbucketPrivate; };
in python2.pkgs.buildPythonApplication rec {
  pname = "sal-bf2556-t1";
  inherit (repo) version src;

  propagatedBuildInputs = [ sal_modules ] ++
    [ (python2.withPackages (ps: with ps; [ grpcio ])) ];
}
