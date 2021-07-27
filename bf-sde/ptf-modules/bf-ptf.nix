{ pname, version, buildSystem, src, patches, bf-drivers, bf-pktpy,
  lib, stdenv, cmake }:

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
## propagated build input or with wrapPythonProgramsIn.

## Make sure we use the same Python version as bf-drivers to make the
## tests depending on the modules from bf-drivers work.
let
  python = bf-drivers.pythonModule;
in if buildSystem.isCmake
   then
     python.pkgs.toPythonModule (stdenv.mkDerivation {
       inherit pname version src patches;
       ## Pass interpreter on to dependent packages
       passthru = {
         inherit python;
       };
       buildInputs = [ python python.pkgs.wrapPython cmake ];
       preConfigure = buildSystem.preConfigure rec {
         package = "ptf-modules";
         cmakeRules = ''
           set(PTF_PKG_DIR "${package}")
           execute_process(
             COMMAND python -c "if True:
               from distutils import sysconfig as sc
               print(sc.get_python_lib(prefix=''', standard_lib=True, plat_specific=True))"
             OUTPUT_VARIABLE PYTHON_SITE
             OUTPUT_STRIP_TRAILING_WHITESPACE)
           set(PYTHON_SITE "''${PYTHON_SITE}/site-packages")
           install(PROGRAMS ''${CMAKE_CURRENT_SOURCE_DIR}/''${BF_PKG_DIR}/''${PTF_PKG_DIR}/bf-ptf/ptf DESTINATION bin RENAME bf-ptf)
           install(DIRECTORY ''${CMAKE_CURRENT_SOURCE_DIR}/''${BF_PKG_DIR}/''${PTF_PKG_DIR}/bf-ptf/src/ DESTINATION ''${PYTHON_SITE}/bf-ptf)
         '';
       };

       postInstall = ''
         python -m compileall $out/lib/${python.libPrefix}/site-packages
       '';

       ## wrapPythonProgramsIn must be able to see the nix-support
       ## directory to follow propagated build inputs and nix-support
       ## is part of the "dev" output.
       pythonPath = [ bf-drivers.dev bf-pktpy ]
                    ++ (with python.pkgs; [ thrift scapy-helper ]);
       postFixup = ''
         wrapPythonProgramsIn $out/bin "$out/bin $pythonPath"
       '';

     })
   else
     python.pkgs.buildPythonApplication rec {
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
