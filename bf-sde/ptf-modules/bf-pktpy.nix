{ pname, version, buildSystem, src, patches, bf-drivers, cmake, stdenv }:

let
  python = bf-drivers.pythonModule;
in if buildSystem.isCmake
   then
     python.pkgs.toPythonModule (stdenv.mkDerivation {
       pname = "bf-pktpy";
       inherit version src patches;
       buildInputs = [ python cmake ];
       propagatedBuildInputs = with python.pkgs;
         [ ipaddress six netifaces psutil ];
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
           install(DIRECTORY ''${CMAKE_CURRENT_SOURCE_DIR}/''${BF_PKG_DIR}/''${PTF_PKG_DIR}/bf-pktpy/bf_pktpy DESTINATION ''${PYTHON_SITE})
         '';
       };
       postInstall = ''
         python -m compileall $out/lib/${python.libPrefix}/site-packages
       '';
     })
   else
     python.pkgs.buildPythonPackage rec {
       pname = "bf-pktpy";
       inherit version src patches;

       propagatedBuildInputs = with python.pkgs;
         [ ipaddress six netifaces psutil ];
       preConfigure = ''pushd bf-pktpy'';
     }
