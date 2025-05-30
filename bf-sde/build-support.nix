### The CMake system used by the SDE is monolithic in the sense that
### everything is built from a single top-level CMakeLists.txt
### file. The Nix packaging splits the components (in the pkgsrc
### directory) into separate derivations to make the whole system more
### modular. To achieve that, we need to do the following:
###
###    * Copy the cmake directory from the global top-level to the
###      component's top-level directory
###
###    * Add some common CMake statements that are part of the
###      top-level CMakeLists.txt in the monolithic build
###
###         * cmake_minimum_required()
###         * A dummy project() that enables C and CXX
###         * Some default C/CXX settings
###         * Set default installation paths
###         * Add local cmake directory to CMAKE_MODULE_PATH
###         * include(ConfigureChecks)
###
###    * Optionally add per-component CMake rules. The top-level
###      CMakeLists.txt contains some rules for each component (it is
###      unclear why those are there instead of in the component's own
###      CMakeLists.txt)
###
### Those modifications are applied to the original source tree of the
### component. The function fixupSrc below creates this modified
### source tree which can be used as a drop-in replacement for the
### "src" attribute in the component's build recipe.
###
### Note: the bf-driver component supports a "standalone" build with
### CMake, but that is intended for building the kernel modules only,
### i.e. it is not possible to build the full drivers package in
### standalone mode. Hence, the procedure above needs to be applied
### here as well.

{ sdeSpec, runCommand, stdenv, lib }:

let
  cmakePreamble = ''
    cmake_minimum_required(VERSION 3.5)
    project(none LANGUAGES C CXX)
    include_directories(\''${CMAKE_CURRENT_BINARY_DIR})

    set(CMAKE_CXX_EXTENSIONS OFF)
    set(CMAKE_C_STANDARD 99)
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    list(APPEND CMAKE_MODULE_PATH "\''${CMAKE_CURRENT_SOURCE_DIR}/cmake")
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)

    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "\''${CMAKE_INSTALL_PREFIX}/lib")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "\''${CMAKE_INSTALL_PREFIX}/lib")
    set(CMAKE_PREFIX_PATH "\''${CMAKE_INSTALL_PREFIX}")
    include(ConfigureChecks)
  '';
in {
  fixupSrc =
    { src, preambleOverride ? false, cmakeRules ? "",
      postCmakeRules ? "", bypass ? false }:

    if bypass
    then
      src
    else
      stdenv.mkDerivation {
        name = "cmake-fixup-src.tar";
        inherit src preambleOverride;
        phases = [ "unpackPhase" "buildPhase" ];
        cmakePatches = sdeSpec.sde.patches.mainCMake or [];
        buildPhase = ''
          if [ -z "$preambleOverride" ]; then
            echo "${cmakePreamble}" >CMakeLists.txt.new
          fi
          echo "${cmakeRules}" >>CMakeLists.txt.new
          [ -f CMakeLists.txt ] && cat CMakeLists.txt >>CMakeLists.txt.new
          echo "${postCmakeRules}" >>CMakeLists.txt.new
          mv CMakeLists.txt.new CMakeLists.txt
          cp -r ${sdeSpec.sde.src}/cmake .
          chmod -R a+w cmake
          for patch in $cmakePatches; do
            patch -p1 <$patch
          done
          tar --transform 's,^\.,archive,' -cf $out .
        '';
      };
}
