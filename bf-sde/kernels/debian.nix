{ arch, common, kbuild, mkKbuild, fetchurl }:

let
  fetch_deb = { name, sha256 }:
    fetchurl {
      url = "http://ftp.ch.debian.org/debian/pool/main/l/linux/${name}";
      inherit sha256;
    };
in mkKbuild.overrideAttrs (_: {
  name = "debian-kbuild";
  unpackPhase = ''
    arch=${fetch_deb arch}
    common=${fetch_deb common}
    kbuild=${fetch_deb kbuild}

    remove_line_from_file () {
      pattern=$1
      file=$2
      grep -v $pattern $file >$file.tmp
      mv $file.tmp $file
    }

    mkdir $out
    ar x $arch
    tar -C $out -xf data.tar.xz ./usr --strip-components 4

    ar x $common
    tar -C $out -xf data.tar.xz ./usr/src --strip-components 4

    ar x $kbuild
    tar -C $out -xf data.tar.xz ./usr/lib --strip-components 4

    ## The current nixpkgs provides binutils 2.31, while newer Debian
    ## kernels use binutils >= 2.32.  This leads to a conflict when
    ## building modules for a kernel which has CONFIG_UNWIDER_ORC
    ## enabled.  In that case, the kernel Makefile applies "objtool
    ## orc generate" to the compiled module, which creates .debug_info
    ## sections that can no longer be read by objdump from binutils
    ## <2.32.  The problem is that objtool comes from the debian
    ## package while objdump comes from nixpkgs.
    ##
    ## The conflict should be resolved once we move to a nixpkgs
    ## version which supports a newer binutils version. Until then,
    ## we work around the issue by disabling ORC unwinding.
    remove_line_from_file CONFIG_UNWINDER_ORC $out/.config
    remove_line_from_file CONFIG_UNWINDER_ORC $out/include/config/auto.conf

    ## .kernelvariables is Debian-specific and, among other things,
    ## selects a particular version of gcc in a Debian-specific manner
    ## (e.g. gcc-8).  We reset this to always just use gcc and make
    ## sure we select a stdenv which supplies a suitable version of
    ## the compiler.
    sed -i -e 's/gcc-.*$/gcc/' $out/.kernelvariables
  '';
})
