## Provide a list of kernels for which the SDE can build its modules.
##
## Each attribute set in the list provides two items.  The first is
## the name of the kernel release exactly as it is reported by "uname
## -r" on a system that runs this kernel.  The second is a derivation
## that reproduces what is expected to be the contents of the
## directory /lib/modules/$(uname -r)/build after installing all
## native packages required for module compilation.  This derivation
## is used by ../generic.nix to perform the actual build of the
## modules.
##
## The creation of /lib/modules/$(uname -r)/build clearly depends
## heavily on the native package manager of the system.  The purpose
## of the logic below is to remove the dependence on those package
## managers to create a distribution-agnostic version of the kernel
## build directory.

callPackage:

let
  mkKbuild = callPackage ./make-kbuild.nix {};
  mk = arg: pkg:
    callPackage pkg (arg // { inherit mkKbuild; });
  mkONL = arg:
    mk arg ./onl.nix;
  mkDebian = arg:
    mk arg ./debian.nix;
  mkMion = arg:
    mk arg ./mion.nix;
in {
  ## Mion/Yocto doesn't currently supply a working kernel build
  ## directory.  We create one by compiling a pristine kernel with the
  ## configuration copied from a running mion image (from
  ## /proc/config.gz).
  mion =
    let
      version = "5.4.49";
      localVersion = "-yocto-standard";
    in {
      release = "${version}${localVersion}";
      build = mkMion {
        inherit version localVersion;
        kbuild = (callPackage ./build-kernel.nix {
          kernel = {
            inherit version localVersion;
            config = ./mion-5.4.49-config.gz;
            sha256 = "0g2psjf2q10mfc3vv6brjn6s2nkg73ll1s04gpshw907d9irpn2m";
          };
        }).dev;
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
    build = mkONL {
      deb = ./onl-kernel-4.14-lts-x86-64-all_1.0.0_amd64.deb;
    };
  };
  ONL10 = {
    ## ONL with Debian10, based on commit 1537d8
    release = "4.19.81-OpenNetworkLinux";
    build = mkONL {
      deb = ./onl-kernel-4.19-lts-x86-64-all_1.0.0_amd64.deb;
    };
  };

  ## Debian splits the kernel build environment into three separate
  ## packages that need to be combined to form the complete build
  ## directory.  The deb files are available for download and don't
  ## need to be stored in the bf-sde-nixpkgs repo.
  Debian10 = {
    ## Standard kernel for Debian10 (buster)
    release = "4.19.0-11-amd64";
    build = mkDebian {
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
  };
}
