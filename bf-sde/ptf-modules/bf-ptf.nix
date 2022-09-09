{ pname, version, buildSystem, src, patches, bf-drivers, bf-pktpy,
  lib, stdenv, cmake, thrift }:

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
       inherit pname version patches;
       src = buildSystem.cmakeFixupSrc {
         inherit src;
         preambleOverride = true;
         ## bf-ptf does not have a CMakeLists.txt. It is built
         ## directly from the top-level. The following rules are
         ## copied from there with appropriate modifications.
         cmakeRules = ''
           cmake_minimum_required(VERSION 3.5)
           project(none LANGUAGES C)
           set(PYTHON_SITE lib/${python.libPrefix}/site-packages)
         '' +
         (if (lib.versionOlder version "9.8.0") then ''
           install(PROGRAMS \''${CMAKE_CURRENT_SOURCE_DIR}/bf-ptf/ptf DESTINATION bin RENAME bf-ptf)
           install(DIRECTORY \''${CMAKE_CURRENT_SOURCE_DIR}/bf-ptf/src/ DESTINATION \''${PYTHON_SITE}/bf-ptf)
         '' else ''
           install(PROGRAMS \''${CMAKE_CURRENT_SOURCE_DIR}/ptf/ptf DESTINATION bin)
           install(DIRECTORY \''${CMAKE_CURRENT_SOURCE_DIR}/ptf/src/ DESTINATION \''${PYTHON_SITE})
         '');
       };
       ## Pass interpreter on to dependent packages
       passthru = {
         inherit python;
       };
       buildInputs = [ python python.pkgs.wrapPython cmake ]
                     ++ lib.optional (lib.versionAtLeast version "9.8.0") thrift;

       postInstall = ''
         python -m compileall $out/lib/${python.libPrefix}/site-packages
       '';

       ## wrapPythonProgramsIn must be able to see the nix-support
       ## directory to follow propagated build inputs and nix-support
       ## is part of the "dev" output.
       pythonPath = [ bf-drivers.dev bf-pktpy ]
                    ## Note: the global thrift shadows that from "with
                    ## python.pkgs", hence the full path below
                    ++ (with python.pkgs; [ python.pkgs.thrift scapy-helper ]
                                          ++ lib.optional (lib.versionAtLeast version "9.7.0")
                                            getmac
                    );
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
