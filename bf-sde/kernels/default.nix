## Provide a set of kernels for which the SDE can build its modules.
##
## The name of each set identifies the kernel and is used as input to
## the buildModules passthru function of the bf-sde package to perform
## the actual build of the kernel modules.
##
## Each set has the following attributes
##
##   release
##     the name of the kernel release exactly as it is reported by
##     "uname -r" on a system which runs that kernel.
##
##   buildTree
##     A derivation which provides a complete kernel build tree
##     in which the kernel modules can be compiled. This is what
##     is usually found in /lib/modules/$(uname -r)/build on
##     a system on which the kernel development packages have
##     been installed by the native package manager of the system.
##
##   patches
##     An optional attribute set of patches to be applied to the
##     bf-drivers source before building the kernel modules.  The
##     names in this set must be SDE versions in the form
##     <major>.<minor>.<patch> and the values must be lists of
##     patches.
##
##   buildModulesOverrides
##     An optional attribute set of overrides for the function
##     returned by ./build-modules.nix.

pkgs:

with pkgs;

let
  mk = arg: pkg:
    let
      mkKbuild = callPackage ./make-kbuild.nix { inherit (arg) patchelfInputs; };
    in
      callPackage pkg (arg.spec // { inherit mkKbuild; });
  mkONL = arg:
    mk arg ./onl.nix;
  mkDebian = arg:
    mk arg ./debian.nix;
  mkMion = arg:
    mk arg ./mion.nix;
in {
  ## Mion stores the kernel build artifacts in
  ## build/tmp-glibc/work-shared/<machine>/kernel-build-artifacts, but
  ## it also requires access to the full kernel sources.  The former
  ## must be present here as a tar archive, the latter is fetched from
  ## the Yocto kernel repository.  The git commit fetched here must
  ## match exactly the commit for the kernel from the version of
  ## https://github.com/NetworkGradeLinux/meta-mion-bsp.git used to
  ## build the mion image, for example
  ## https://github.com/NetworkGradeLinux/meta-mion-bsp/blob/dunfell/meta-mion-accton/recipes-kernel/linux/linux-yocto_5.4.bbappend
  mion = rec {
    release = "5.4.49-yocto-standard";
    buildTree = mkMion {
      spec = {
        source = fetchurl {
          url = "http://git.yoctoproject.org/cgit/cgit.cgi/linux-yocto/snapshot/v5.4.49-129-gec485bd4afef.tar.gz";
          sha256 = "1cvm4g6x7z93rj071jcqgmml91pgy8nf6ablbj50j1aawd2rza5q";
        };
        kbuild = ./5.4.49-yocto-standard-build.xz;
      };
      patchelfInputs = [ openssl_1_1.out elfutils ];
    };
    buildModulesOverrides = {
      stdenv = gcc8Stdenv;
    };
    patches = {
      "9.1.1" = [ ./bf-drivers-9.1.1.patch ];
    };
  };

  ## OpenNetworkLinux creates a single deb file that essentially
  ## contains the full build directory.  The deb files themselves are
  ## stored in this repo, because they are not available for download
  ## (they are the result of building ONL
  ## locally).
  ONL9 = {
    ## ONL with Debian9 created from commit 7c3bfd
    release = "4.14.151-OpenNetworkLinux";
    buildTree = mkONL {
      spec = {
        deb = ./onl-kernel-4.14-lts-x86-64-all_1.0.0_amd64.deb;
      };
      patchelfInputs = [ elfutils ];
    };
  };
  ONL10 = {
    ## ONL with Debian10, based on commit 1537d8
    release = "4.19.81-OpenNetworkLinux";
    buildTree = mkONL {
      spec = {
        deb = ./onl-kernel-4.19-lts-x86-64-all_1.0.0_amd64.deb;
      };
      patchelfInputs = [ openssl_1_1.out elfutils ];
    };
  };

  ## Debian splits the kernel build environment into three separate
  ## packages that need to be combined to form the complete build
  ## directory.  The deb files are available for download and don't
  ## need to be stored in the bf-sde-nixpkgs repo.
  Debian10 = {
    ## Standard kernel for Debian10 (buster)
    release = "4.19.0-11-amd64";
    buildTree = mkDebian {
      spec = {
        arch = {
          name = "linux-headers-4.19.0-11-amd64_4.19.146-1_amd64.deb";
          sha256 = "1j0d10898sfnsw58fg7f28m4xx0gnrvm6jvdyxj7a8gzp02j1dzi";
        };
        common = {
          name = "linux-headers-4.19.0-11-common_4.19.146-1_all.deb";
          sha256 = "1s1qyfaywkzdwrs5lk10g9gg7pskryiqrnvbqayk6cd4sc90hl9v";
        };
        kbuild = {
          name = "linux-kbuild-4.19_4.19.152-1_amd64.deb";
          sha256 = "0j4w4jiyw8jpdgxdf9mwk13772hb0zkbykj9k5hyh7jaivgxvsc5";
        };
      };
      patchelfInputs = [ openssl_1_1.out elfutils ];
    };
  };
}
