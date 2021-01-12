{ pname, version, src, patches, lib, stdenv, python3,
  bf-drivers-src, bf-syslibs }:

## Note: creating a "dev" output for this package with the default
## method creates a dependency cycle between the "out" and "dev"
## outputs.  This should be investigated at some point.
stdenv.mkDerivation {
  inherit pname version src patches;

  buildInputs = [ bf-syslibs.dev python3 ];

  enableParallelBuilding = true;
  dontDisableStatic = true;

  ## bf-python is an awful mess in 9.3.0.  bf-utils contains a full
  ## Python interpreter (version 3.4) with a customized IPython
  ## module. This is called from bf_switchd when "bfrt_python" is
  ## invoked.  The entry-point is the start_bfrt() function of
  ## bfrtcli.py. So far, so good.
  ##
  ## The problem is that bfrtcli.py along with 4 other modules is
  ## included in this package as well as in the bf-drivers package,
  ## but the verions differ. From the way the modules are installed by
  ## p4studio, the modules from bf-drivers overwrite those of bf-utils
  ## when installed into the common SDE_INSTALL tree.  This "trick"
  ## doesn't work here.  So, what we do is get those files from the
  ## bf-drivers source before we build.
  preBuild =
    (if (lib.versionAtLeast version "9.3.0")
      then
        ''
          mkdir tmp
          tar -C tmp -xf ${bf-drivers-src} --strip-component 1
          cp tmp/src/bf_rt/bf_rt_python/bfrt* third-party/bf-python/Lib
        ''
      else
        "") +
    ''
      patchShebangs third-party
    '';
}
