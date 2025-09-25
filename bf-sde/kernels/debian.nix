{ snapshotTimestamp, arch, common, kbuild, source, mkKbuild, fetchurl,
  stdenv, system, pahole, writeShellScript }:

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
    inputs = [ pahole ];
    prep = kernelStdenv:
      let
        gnuPrefix = "${system}-gnu";
        debianGccSystemAliases = stdenv.mkDerivation {
          name = "debian-gcc-aliases";
          src = null;
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out/bin
            ln -s ${kernelStdenv.cc}/bin/gcc $out/bin/${gnuPrefix}-gcc
            ln -s ${kernelStdenv.cc}/bin/ld.bfd $out/bin/${gnuPrefix}-ld
            ln -s ${kernelStdenv.cc}/bin/objcopy $out/bin/${gnuPrefix}-objcopy
          '';
        };
      in writeShellScript "debian-kbuild-prep" ''
        PATH=''${PATH}:${debianGccSystemAliases}/bin
    '';
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

    ## .kernelvariables is Debian-specific and, among other things,
    ## selects a particular version of gcc in a Debian-specific manner
    ## (e.g. gcc-8).  We reset this to always just use gcc and make
    ## sure we select a stdenv which supplies a suitable version of
    ## the compiler.
    sed -i -e 's/gcc-.*$/gcc/' $out/.kernelvariables
  '';
})
