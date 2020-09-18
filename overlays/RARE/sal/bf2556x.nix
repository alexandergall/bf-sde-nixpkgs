{ python2, sal_modules }:

python2.pkgs.buildPythonApplication rec {
  pname = "sal-bf2556-t1";
  version = "20.6.23";

  src = /home/gall/rare-bf2556x-1t;

  propagatedBuildInputs = [ sal_modules ] ++
    [ (python2.withPackages (ps: with ps; [ grpcio ])) ];
}
