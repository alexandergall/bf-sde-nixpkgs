### Starting with 9.5.0, Intel converted the build system from GNU
### autotools to CMake. The old system still exists at least in 9.5.0
### and 9.6.0 but is no longer maintained and will be removed
### completely at some point.  We start using CMake with 9.6.0.
###
### The CMake-based build system requires some non-trivial changes in
### the Nix expression.  The main difference is that with the old
### systems the sub-packages could be built completely independently
### from each other, where as with the new system the entire SDE is
### built from a single top-level CMakeLists.txt file. It is still
### possible to build the components separately by the following
### method.
###
### Since the CMakeLists.txt files in the sub-packages are not
### self-contained, we need to apply a suitable version of the
### top-level file to each of them.  By "suitable" we mean essentially
### that we only retain the clauses that pertain to the subpackage.
###
### To do this, we first create a basic top-level file that only
### contains configuration options and the global ConfigureChecks. In
### a sub-package's preConfigure phase, we do the following
###
###   * Add a directory cmake-toplevel
###   * Copy the global CMakeLists.txt and the cmake module
###     directory to cmake-toplevel
###   * Append a cmake fragment that performs the
###     sub-package specific configuration
###   * To re-create the original hierarchy
###      * Create a "pkgsrc" directory
###      * Create a sub-package-specific symlink in "pkgsrc"
###        pointing to the effective source directory. The name
###        of the link is chosen to be the same used in the original
###        CMakeLists.txt file, e.g. "bf-utils" or "bf-syslibs"
###        for convenience
###
### cmake is then invoked from inside the cmake-toplevel directory.
### The effect is the same as the original cmake procedure but limited
### to a single sub-package.
###
### This mechanism is implemented as a specific preConfigure phase
### created by the "preConfigure" helper function below.
###
### The top-level CMakeLists.txt must be created for each new SDE
### version in bf-sde/build-system/CMakeLists.txt-${version}. The
### per-packet fragments may have to be adapted as well.

{ sdeSpec, runCommand, lib }:

let
  version = sdeSpec.version;
  sdeSrc = runCommand "bf-sde-${version}-unpacked" {} ''
    mkdir $out
    tar -C $out -xf ${sdeSpec.sde.src} --strip-components 1
  '';
in rec {
  isCmake = lib.strings.versionAtLeast version "9.6.0" &&
            builtins.pathExists (sdeSrc + "/CMakeLists.txt");
  topLevel = assert isCmake; ./. + "/CMakeLists.txt-${version}";
  cmakeDir = assert isCmake; runCommand "cmake-extract" {} ''
    mkdir $out
    cp -r ${sdeSrc}/cmake $out
  '';
  preConfigure =
    { package, cmakeRules, preCmds ? "",
      postCmds ? "", alternativeCmds ? "" }:
    if isCmake then
      preCmds + ''
        mkdir cmake-toplevel
        cp ${topLevel} cmake-toplevel/CMakeLists.txt
        chmod a+w cmake-toplevel/CMakeLists.txt
        cat <<"EOF" >>cmake-toplevel/CMakeLists.txt
        ${cmakeRules}
        EOF
        cp -r ${cmakeDir}/* cmake-toplevel
        chmod -R a+w cmake-toplevel/cmake
        mkdir cmake-toplevel/pkgsrc
        ln -rs . cmake-toplevel/pkgsrc/${package}
        cmakeDir=../cmake-toplevel
      '' + postCmds
    else
      alternativeCmds;
}
