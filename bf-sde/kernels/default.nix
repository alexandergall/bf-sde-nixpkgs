## Build the SDE kernel modules for a set of kernels specified in the
## set "kernels" below. Return a set with the names of the kernels as
## attributes and the modules packages as values.
##
##
## The name of each set identifies the kernel and is used as input to
## the buildModules passthru function of the bf-sde package to perform
## the actual build of the kernel modules.
##
## Each set has the following attributes
##
##   kernelRelease
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
##     An optional attribute set of overrides for the derivation
##     returned by ./build-modules.nix.

{ bf-drivers-src, pkgs, callPackage, drvsWithKernelModules }:

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
  mkModules = kernelID: spec':
    let
      defaults = {
        patches = [];
        buildModulesOverrides = {};
      };
      spec = defaults // spec';
    in (callPackage ./build-modules.nix {
      inherit kernelID spec drvsWithKernelModules;
      src = bf-drivers-src;
    }).override spec.buildModulesOverrides;

  kernels = {
    ## Mion stores the kernel build artifacts in
    ## build/tmp-glibc/work-shared/<machine>/kernel-build-artifacts, but
    ## it also requires access to the full kernel sources.  The former
    ## must be present here as a tar archive, the latter is fetched from
    ## the Yocto kernel repository.  The git commit fetched here must
    ## match exactly the commit for the kernel from the version of
    ## https://github.com/NetworkGradeLinux/meta-mion-bsp.git used to
    ## build the mion image, for example
    ## https://github.com/NetworkGradeLinux/meta-mion-bsp/blob/dunfell/meta-mion-accton/recipes-kernel/linux/linux-yocto_5.4.bbappend
    mion = {
      kernelRelease = "5.4.49-yocto-standard";
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
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };

    ## OpenNetworkLinux creates a single deb file that essentially
    ## contains the full build directory.  The deb files themselves are
    ## stored in this repo, because they are not available for download
    ## (they are the result of building ONL
    ## locally).
    ONL9 = {
      ## ONL with Debian9 created from commit 7c3bfd
      kernelRelease = "4.14.151-OpenNetworkLinux";
      buildTree = mkONL {
        spec = {
          deb = ./onl-kernel-4.14-lts-x86-64-all_1.0.0_amd64.deb;
        };
        patchelfInputs = [ elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };
    ONL10 = {
      ## ONL with Debian10, based on commit 1537d8
      kernelRelease = "4.19.81-OpenNetworkLinux";
      buildTree = mkONL {
        spec = {
          deb = ./onl-kernel-4.19-lts-x86-64-all_1.0.0_amd64.deb;
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };

    ## Debian splits the kernel build environment into three separate
    ## packages that need to be combined to form the complete build
    ## directory.  The deb files are available for download and don't
    ## need to be stored in the bf-sde-nixpkgs repo.
    Debian10_8 = {
      kernelRelease = "4.19.0-14-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20210601T022916Z";
          arch = {
            name = "linux-headers-4.19.0-14-amd64_4.19.171-2_amd64.deb";
            sha256 = "0f0m80ml35wc26z03rmlv159pdq5k0c3c8596827945347h0k1f4";
          };
          common = {
            name = "linux-headers-4.19.0-14-common_4.19.171-2_all.deb";
            sha256 = "0vlrqy2av70hbckdzfnfjxzgqfi5czcffvw5by3ipy94vqw3xy73";
          };
          kbuild = {
            name = "linux-kbuild-4.19_4.19.181-1_amd64.deb";
            sha256 = "01ygxscag9r6pqs1vfydprglqd2g5pa9c49ja5na68bpw3vnzdzv";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };
    Debian10_9 = {
      kernelRelease = "4.19.0-16-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20210601T022916Z";
          arch = {
            name = "linux-headers-4.19.0-16-amd64_4.19.181-1_amd64.deb";
            sha256 = "05as3x898missk9277bb51drzg4zgk0mdd4ij8sninpnws73fg75";
          };
          common = {
            name = "linux-headers-4.19.0-16-common_4.19.181-1_all.deb";
            sha256 = "07nd5sjbygwb9r4lbl347hyz1ymf6s38kfh2gf604hnrh5nkqvfm";
          };
          kbuild = {
            name = "linux-kbuild-4.19_4.19.181-1_amd64.deb";
            sha256 = "01ygxscag9r6pqs1vfydprglqd2g5pa9c49ja5na68bpw3vnzdzv";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };
    Debian10_10 = {
      kernelRelease = "4.19.0-17-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20210622T083255Z";
          arch = {
            name = "linux-headers-4.19.0-17-amd64_4.19.194-1_amd64.deb";
            sha256 = "0z4nc5sinmhyy1zz91zvbjjj5jarb889sxidmihayvn0m8k3pskw";
          };
          common = {
            name = "linux-headers-4.19.0-17-common_4.19.194-1_all.deb";
            sha256 = "1hzjb4dw5f9n47c311yihldi9s6scly6pd6m8i285d25nj1mrw1v";
          };
          kbuild = {
            name = "linux-kbuild-4.19_4.19.194-1_amd64.deb";
            sha256 = "0vf44ks0naqbnbkm8ydlh591nr934k83dkq53jm53nk8acdbbdji";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };
    Debian11_0 = {
      kernelRelease = "5.10.0-8-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20210916T090242Z";
          arch = {
            name = "linux-headers-5.10.0-8-amd64_5.10.46-4_amd64.deb";
            sha256 = "1lpriwpsq74ym6hyzh75bgkf2r8kkb4sdjmff5hlzbizdk6skgr4";
          };
          common = {
            name = "linux-headers-5.10.0-8-common_5.10.46-4_all.deb";
            sha256 = "1vh1fwrqglbv049vazn038si6j5nmdrsjaj1dfr1bchm2bjvizs8";
          };
          kbuild = {
            name = "linux-kbuild-5.10_5.10.46-4_amd64.deb";
            sha256 = "1ihg819bmgn3934xwnjnbclmvki1cb562a3gwa3dnykrqp7wcm3f";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches =
        let
          patch = [ ./bf-drivers-kernel-5.8.patch ];
        in {
          "9.1.1" = patch ++ [ ./bf-drivers-9.1.1.patch ];
          "9.2.0" = patch;
          "9.3.0" = patch;
          "9.3.1" = patch;
          "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
        };
    };
    Debian11_3 = {
      kernelRelease = "5.10.0-13-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20220429T092639Z";
          arch = {
            name = "linux-headers-5.10.0-13-amd64_5.10.106-1_amd64.deb";
            sha256 = "1ha5b5ia3pqv9qchrhnmn9rg7ry6b9qfjy64d03h49rvnqry3s58";
          };
          common = {
            name = "linux-headers-5.10.0-13-common_5.10.106-1_all.deb";
            sha256 = "0df6i02m4ckp004mlmmgv64z2r7vp3yzndsgh89vj7iljcwg0s8g";
          };
          kbuild = {
            name = "linux-kbuild-5.10_5.10.106-1_amd64.deb";
            sha256 = "0pzzx5qjnkgcxdpl7rx9zpkqnp1d6mnqw73d8w3nqanjn8cgwsmh";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches =
        let
          patch = [ ./bf-drivers-kernel-5.8.patch ];
        in {
          "9.1.1" = patch ++ [ ./bf-drivers-9.1.1.patch ];
          "9.2.0" = patch;
          "9.3.0" = patch;
          "9.3.1" = patch;
          "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
        };
    };
  };
in
  builtins.mapAttrs mkModules kernels
