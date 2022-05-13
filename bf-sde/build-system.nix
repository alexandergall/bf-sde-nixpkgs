### Starting with 9.5.0, Intel converted the build system from GNU
### autotools to CMake. The old system still exists at least in 9.5.0
### and 9.6.0 but is no longer maintained and will be removed
### completely at some point.  We start using CMake with 9.6.0.
###
### The CMake-based build system requires some non-trivial changes in
### the Nix expression.  The main difference is that with the old
### system, the sub-packages could be built completely independently
### from each other, where as with the new system the entire SDE is
### built from a single top-level CMakeLists.txt file.
###
### To make each component self-contained, we need to do the
### following:
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
### component. The function cmakeFixupSrc below creates this modified
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
  version = sdeSpec.version;
  cmakePatches = sdeSpec.sde.patches.mainCMake or [];
  applyPatch = patch:
    "patch -d $out -p1 <${patch}";
  applyPatches = builtins.concatStringsSep "\n"
    (map applyPatch cmakePatches);
  topLevelCmake = runCommand "bf-sde-${version}-cmake" {} ''
    mkdir $out
    tar -C $out -xf ${sdeSpec.sde.src} --wildcards '*/cmake' --strip-components 1
    ${applyPatches}
  '';
  cmakePreamble = ''
    cmake_minimum_required(VERSION 3.5)
    project(none LANGUAGES C CXX)
    include_directories(\''${CMAKE_CURRENT_BINARY_DIR})

    set(CMAKE_CXX_EXTENSIONS OFF)
    set(CMAKE_C_STANDARD 99)
    set(CMAKE_CXX_STANDARD 11)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    list(APPEND CMAKE_MODULE_PATH "\''${CMAKE_CURRENT_SOURCE_DIR}/cmake")
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)

    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "\''${CMAKE_INSTALL_PREFIX}/lib")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "\''${CMAKE_INSTALL_PREFIX}/lib")
    set(CMAKE_PREFIX_PATH "\''${CMAKE_INSTALL_PREFIX}")
    include(ConfigureChecks)
  '';
in rec {
  isCmake = lib.strings.versionAtLeast version "9.6.0";
  cmakeFixupSrc = { src, preambleOverride ? false, cmakeRules ? "",
                    postCmakeRules ? "", bypass ? false }:
    if (isCmake || bypass) then
      stdenv.mkDerivation {
        name = "cmake-fixup-src.tar";
        inherit src preambleOverride;
        phases = [ "unpackPhase" "buildPhase" ];
        buildPhase = ''
          if [ -z "$preambleOverride" ]; then
            echo "${cmakePreamble}" >CMakeLists.txt.new
          fi
          echo "${cmakeRules}" >>CMakeLists.txt.new
          [ -f CMakeLists.txt ] && cat CMakeLists.txt >>CMakeLists.txt.new
          echo "${postCmakeRules}" >>CMakeLists.txt.new
          mv CMakeLists.txt.new CMakeLists.txt
          cp -r ${topLevelCmake}/cmake .
          tar --transform 's,^\.,archive,' -cf $out .
        '';
      }
    else
      src;
}
