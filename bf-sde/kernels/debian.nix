{ snapshotTimestamp, arch, common, kbuild, source, mkKbuild, fetchurl,
  stdenv, pahole }:

let
  fetch_deb = { name, sha256 }:
    fetchurl {
      url = "http://snapshot.debian.org/archive/debian/${snapshotTimestamp}/pool/main/l/linux/${name}";
      inherit sha256;
    };
in mkKbuild.overrideAttrs (_: {
  name = "debian-kbuild";
  passthru = {
    source = stdenv.mkDerivation {
      name = "debian-kbuild-kernel-source.tar.xz";
      unpackPhase = ''
        source=${fetch_deb source}
        ar x $source
        tar -xf data.tar.* ./usr/src --wildcards linux-source-* --strip-components 3
        mv linux-source-* $out
      '';
      dontInstall = true;
    };
  };
  unpackPhase = ''
    arch=${fetch_deb arch}
    common=${fetch_deb common}
    kbuild=${fetch_deb kbuild}

    mkdir $out
    ar x $arch
    tar -C $out -xf data.tar.xz ./usr --strip-components 4

    ar x $common
    tar -C $out -xf data.tar.xz ./usr/src --strip-components 4

    ar x $kbuild
    tar -C $out -xf data.tar.xz ./usr/lib --strip-components 4
  '' +
  ## .kernelvariables is Debian-specific and, among other things,
  ## selects a particular version of gcc in a Debian-specific manner
  ## (e.g. gcc-8).  We reset this to always just use gcc and make sure
  ## we select a stdenv which supplies a suitable version of the
  ## compiler. Newer kernels also enable cross-compile overrides by
  ## default, which changes the name of executables
  ## (e.g. x86_64-linux-gnu-gcc). Those aliases don't exist in stdenv,
  ## but we can safely disable cross compilation completely to avoid
  ## this problem.
  ''
    sed -i -e 's/gcc-.*$/gcc/;/override CROSS_COMPILE/d' $out/.kernelvariables
  '' +
  ## For 6.1 kernels (Debian 12), pahole is optional. This has changed
  ## some time between 6.1 and 6.12 (Debian 13). Enabling it for all
  ## kernels by setting the path explicitly seems to work fine. Note
  ## that we can't declare it as build input because it won't be
  ## executed until the kbuild environment is used somewhere else. We
  ## could declare it as propagated build input, which would seem
  ## logical, and then declare this derivation as build input whenever
  ## it is used by another derivation. However, that won't work
  ## because it would expose the kbuild include directory to the other
  ## derivation, which would break things. So for now, we try to
  ## maintain the current state that we don't use the regular
  ## dependency mechanism for the kbuild environment.
  ''
    sed -i -e 's!= pahole!= ${pahole}/bin/pahole!' $out/Makefile
  '';
})
