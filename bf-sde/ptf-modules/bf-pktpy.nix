{ pname, version, buildSystem, src, patches, bf-drivers, cmake, stdenv }:

let
  python = bf-drivers.pythonModule;
in if buildSystem.isCmake
   then
     python.pkgs.toPythonModule (stdenv.mkDerivation {
       pname = "bf-pktpy";
       inherit version patches;
       src = buildSystem.cmakeFixupSrc {
         inherit src;
         preambleOverride = true;
         ## bf-pktpy does not have a CMakeLists.txt. It is built
         ## directly from the top-level. The following rules are
         ## copied from there with appropriate modifications.
         cmakeRules = ''
           install(DIRECTORY \''${CMAKE_CURRENT_SOURCE_DIR}/bf-pktpy/bf_pktpy DESTINATION lib/${python.libPrefix}/site-packages)
         '';
       };
       buildInputs = [ python cmake ];
       propagatedBuildInputs = with python.pkgs;
         [ six netifaces psutil ];
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
