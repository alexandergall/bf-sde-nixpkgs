{ pname, version, src, patches, bf-drivers, bf-pktpy, lib }:

## The PTF itself does not depend on bf-drivers, but some of the tests
## run by it do.  We are supposed to pass additional modules on to the
## tests via PYTHONPATH. However, bf-drivers contains a package in the
## "google" namespace which does not work with PYTHONPATH alone.
## Namespace packages also require the
## site-packages directory to be added as a site directory via
## site.addsitedir() to have the *.pth files read. This only happens
## when a package is added inside a Python wrapper, which uses
## NIX_PYTHONPATH and some magic in a Nix-specific
## sitecustomize.py. That's what happens here with bf-drivers as
## propagated build input.

## Make sure we use the same Python version as bf-drivers to make the
## tests depending on the modules from bf-drivers work.
let
  python = bf-drivers.pythonModule;
in python.pkgs.buildPythonApplication rec {
  inherit pname version src patches;

  ## Pass interpreter on to dependent packages
  passthru = {
    inherit python;
  };

  propagatedBuildInputs =
    [ bf-drivers bf-pktpy ]
    ++ (with python.pkgs; [ thrift scapy-helper]);

  preConfigure = ''pushd bf-ptf'';
  postInstall = ''
    mv $out/bin/ptf $out/bin/bf-ptf
  '';
}
