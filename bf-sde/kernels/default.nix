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

{ bf-drivers-src, pkgs, version, callPackage, drvsWithKernelModules }:

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
        baseboardBlacklist = [];
      };
      spec = defaults // spec';
    in (callPackage ./build-modules.nix {
      inherit kernelID spec drvsWithKernelModules;
      src = bf-drivers-src;
    }).override spec.buildModulesOverrides;

  ## Additional modules for Debian 11 kernels
  additionalModulesDebian11 = {
    inventec = [
      {
        directory = "drivers/i2c/muxes";
        makeFlags = [
          "CONFIG_I2C_MUX_PCA954x=m"
        ];
      }
      {
        directory = "drivers/gpio";
        makeFlags = [
          "CONFIG_GPIO_ICH=m"
        ];
      }
    ];
    netberg_710 = [
      {
        directory = "drivers/i2c/muxes";
        makeFlags = [
          "CONFIG_I2C_MUX_PCA954x=m"
        ];
      }
      {
        directory = "drivers/gpio";
        makeFlags = [
          "CONFIG_GPIO_ICH=m"
          "CONFIG_GPIO_PCA953X=m"
        ];
      }
      {
        directory = "drivers/hwmon/pmbus";
        makeFlags = [
          "CONFIG_PMBUS=m"
          "CONFIG_SENSORS_PMBUS=m"
        ];
      }
    ];
  };
  kernels = {
    ## This pseudo-kernel can be selected to have ./build-modules.nix
    ## create a dummy package that will cause a runtime error when an
    ## attempt is made to load one of the kernel modules from the
    ## module wrapper. It is intended primarily to allow the model
    ## platforms to be included in standalone installers just like any
    ## other platform. In that case, the dummy package is not used
    ## since building a P4 program for the model platforms does not
    ## generate a module wrapper at all. However, the release slice
    ## for the model is still expected to contain a kernel module
    ## derivation.
    none = {
      kernelRelease = "none";
      buildTree = builtins.throw "Can't build modules for the \"none\" pseudo-kernel";
    };
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
      disable = true;
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
      baseboardBlacklist = [ "netberg_710" ];
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
      disable = true;
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
      disable = true;
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
      disable = true;
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
          source = {
            name = "linux-source-4.19_4.19.181-1_all.deb";
            sha256 = "0x6z841l996dqhmz3wx5f80rrb9qpw31glsd5cblfbcnn4d0m39a";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };
    Debian10_9 = {
      disable = true;
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
          source = {
            name = "linux-source-4.19_4.19.181-1_all.deb";
            sha256 = "0x6z841l996dqhmz3wx5f80rrb9qpw31glsd5cblfbcnn4d0m39a";
          };
        };
        patchelfInputs = [ openssl_1_1.out elfutils ];
      };
      patches = {
        "9.6.0" = [ ./bf-drivers-bf-knet-9.6.0.patch ];
      };
    };
    Debian10_10 = {
      disable = true;
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
          source = {
            name = "linux-source-4.19_4.19.194-1_all.deb";
            sha256 = "00y8wkqywsbafgs6s802px7bi6chpsj68m6ks8l4k9vg1i310k55";
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
          source = {
            name = "linux-source-5.10_5.10.46-4_all.deb";
            sha256 = "18qmhr93k2fbghb103grvfswmqqgfi2f7bbs2z2b36h37hi8wsrs";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
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
          source = {
            name = "linux-source-5.10_5.10.106-1_all.deb";
            sha256 = "1vgn7dd4j7m884slm56dqllb36c0b4bq0mbdbrr6a0gbm5h9ra9f";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian11_4 = {
      kernelRelease = "5.10.0-16-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20220728T033224Z";
          arch = {
            name = "linux-headers-5.10.0-16-amd64_5.10.127-2_amd64.deb";
            sha256 = "100sivslj7fljf29s3nvdnp8xn7533n3x09vrxqgcmgh5rffcsmc";
          };
          common = {
            name = "linux-headers-5.10.0-16-common_5.10.127-2_all.deb";
            sha256 = "0dn5kif58wq3rjnqvk0rdfpx5rmwzqhjd8197ak0nj3fsfrf2fld";
          };
          kbuild = {
            name = "linux-kbuild-5.10_5.10.127-2_amd64.deb";
            sha256 = "10ywdrr89hhyzzyw4dn8iy0ggwrpb9x94s6pnz52wipckq13q99k";
          };
          source = {
            name = "linux-source-5.10_5.10.127-2_all.deb";
            sha256 = "15ajv2i1mjlr8ljnyxbxjwjbl20hsgrcq2cx4a44635jx84b39ak";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian11_6 = {
      kernelRelease = "5.10.0-20-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20230404T204441Z";
          arch = {
            name = "linux-headers-5.10.0-20-amd64_5.10.158-2_amd64.deb";
            sha256 = "0gxlnwlblw8qapagvndrycrzixdn0kainp5k0q7xzjbxcgpl8c0i";
          };
          common = {
            name = "linux-headers-5.10.0-20-common_5.10.158-2_all.deb";
            sha256 = "0986hzwp9pph81n4i2p0qzgzdqwrgiw5kzshd49s38df4kbr9znj";
          };
          kbuild = {
            name = "linux-kbuild-5.10_5.10.158-2_amd64.deb";
            sha256 = "0d5941h5gv08hbh08d99ldnijsvvkm1wg4vc17ipwmg4sy39018k";
          };
          source = {
            name = "linux-source-5.10_5.10.158-2_all.deb";
            sha256 = "1x0h5rrq3xdq83bsj5c4lla4ssni8nrgfaj4wa4yd8z4v83w1rim";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian11_7 = {
      kernelRelease = "5.10.0-22-amd64";
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20230626T030930Z";
          arch = {
            name = "linux-headers-5.10.0-22-amd64_5.10.178-3_amd64.deb";
            sha256 = "00h8l01aia5chhjnvp084yly1944d58v8id4gfasi1zp8q0dpm0b";
          };
          common = {
            name = "linux-headers-5.10.0-22-common_5.10.178-3_all.deb";
            sha256 = "1vkrwzbg4xbcldl52ilmj3hahxqwf1awddlbij7zsagsgi609vw1";
          };
          kbuild = {
            name = "linux-kbuild-5.10_5.10.178-3_amd64.deb";
            sha256 = "0n3zkfbkbwa63rvkj4p2s4wmfds2dlrviyg28lk69n3k1s7r8kky";
          };
          source = {
            name = "linux-source-5.10_5.10.178-3_all.deb";
            sha256 = "0n6hsnlbwj2qlajx7vrlanip8m849w7yazjixm5fc2rncwydj4sd";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_0 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-9-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20230626T030930Z";
          arch = {
            name = "linux-headers-6.1.0-9-amd64_6.1.27-1_amd64.deb";
            sha256 = "0nc4g0s4bxk39l8mvdk7wjh7h1fmqm1q0yxdk53bhx3jsa5r3v0d";
          };
          common = {
            name = "linux-headers-6.1.0-9-common_6.1.27-1_all.deb";
            sha256 = "1pqs4rwksayy0a6wj4mkdwlg3fl1733i8c7vb1w2bfkpzd9br3q4";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.27-1_amd64.deb";
            sha256 = "1n8xj83wh5gh4g3gfv7lwr519xl4m2419mpyvhjd113xp0qkf22f";
          };
          source = {
            name = "linux-source-6.1_6.1.27-1_all.deb";
            sha256 = "16pci1xmcakbp4yhjsg5nyqpi0in933abj5g7hc8qaw45z207lwx";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_1 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-10-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20230725T030258Z";
          arch = {
            name = "linux-headers-6.1.0-10-amd64_6.1.38-1_amd64.deb";
            sha256 = "1sjby5li8rkqvziy6b00ic3zv2vfs5lrcfcj3vqiqcjxhb4kdy9x";
          };
          common = {
            name = "linux-headers-6.1.0-10-common_6.1.38-1_all.deb";
            sha256 = "06ns24kin2a703m40y8xbf44zbv73k6jbiv5kxln3yiid0i3m60q";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.38-1_amd64.deb";
            sha256 = "0sc2lwxwp0ishxpi46gc533zk11dfcigi1jh6736mcs4hp67kj02";
          };
          source = {
            name = "linux-source-6.1_6.1.38-1_all.deb";
            sha256 = "1ilkpajm20zjd4cx4ih0vqilxn62fil45qn5x8nn3f996vzldka3";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_4 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-15-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20240107T145339Z";
          arch = {
            name = "linux-headers-6.1.0-15-amd64_6.1.66-1_amd64.deb";
            sha256 = "0wbflh9n2p3lr4mss084d43lzzda14zz0qc7hsabixkz13znhfg1";
          };
          common = {
            name = "linux-headers-6.1.0-15-common_6.1.66-1_all.deb";
            sha256 = "0sfk7scvyrwv5d19ar615vx2cczda8nr6rrlb4p5md0gnhp88sip";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.66-1_amd64.deb";
            sha256 = "10rif4awvrwpa2fymrxv3a69r36kkq7lq0bqi6icpds7k8bpdx64";
          };
          source = {
            name = "linux-source-6.1_6.1.66-1_all.deb";
            sha256 = "1w0cqwswl3gh9hk6rmr5lrdp86akq4dzxwv5b138162ah2qa81c9";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_5 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-18-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20240220T150546Z";
          arch = {
            name = "linux-headers-6.1.0-18-amd64_6.1.76-1_amd64.deb";
            sha256 = "1hkpryaysiivdrmh7w9f2rv5bn7qcnbg4pdvp36livsckgv0gjjp";
          };
          common = {
            name = "linux-headers-6.1.0-18-common_6.1.76-1_all.deb";
            sha256 = "15svcq9iqbmncyaya965a1xaa3x79pb1wicp56ps8iqxkwiwzavv";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.76-1_amd64.deb";
            sha256 = "142yyf27cpidabkm0r44dd0j0kwf9h1d7jrlcpy3sjrf2wv66iaj";
          };
          source = {
            name = "linux-source-6.1_6.1.76-1_all.deb";
            sha256 = "091cvp003q85f10220qaznglamqc2avg28y7jpyiw2173mh218ny";
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_6 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-22-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20240724T083012Z";
          arch = {
            name = "linux-headers-6.1.0-22-amd64_6.1.94-1_amd64.deb";
            sha256 = "0s7mxf3q0ri6g2sy3fj9ck2bgiffqk7q3mjk1i2szqrrfh7kcvil";
          };
          common = {
            name = "linux-headers-6.1.0-22-common_6.1.94-1_all.deb";
            sha256 = "11b8cas5krhyh6dhyskhnmnpx63dqki6w609ky9kgnnpr30afm04";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.94-1_amd64.deb";
            sha256 = "17jbsq01ry9cr5y4y4gxmfvv0jax6kidf1r0sf7pw5h4yhyjzby6";
          };
          source = {
            name = "linux-source-6.1_6.1.94-1_all.deb";
            sha256 = "1z73a26lc9zq5pgk1hmdqr1hrh2a86bmskymv9bqhi46nmzqlfdh";
          };
        };
        patchelfInputs = [ elfutils ];
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_7 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-25-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20241108T203442Z";
          arch = {
            name = "linux-headers-6.1.0-25-amd64_6.1.106-3_amd64.deb";
            sha256 = "1bazm5mx0n4l5fg8aay8vxxi3dg3xc35j1npi2h4c3m7ggjqwcv0";
          };
          common = {
            name = "linux-headers-6.1.0-25-common_6.1.106-3_all.deb";
            sha256 = "1iazyv8r2an32991fnnsj760w7aj920pqmxb31riqisq0w9dqcrp";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.106-3_amd64.deb";
            sha256 = "0shrkdg0241f6aqkvq9nmbp18g4hxbalj8hs7wj07xn3jcrmj89p";
          };
          source = {
            name = "linux-source-6.1_6.1.106-3_all.deb";
            sha256 = "10xfbn0r8qmx7wrhdmyca0r12xqz6zcp040ndcafjnc0jn0bp7n8";
          };
        };
        patchelfInputs = [ elfutils ];
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_8 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-27-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20241111T025602Z";
          arch = {
            name = "linux-headers-6.1.0-27-amd64_6.1.115-1_amd64.deb";
            sha256 = "13w0wkyb1hql672vk9rp3dlcp7w8s5nga0f9krgkvp4njzf5br00";
          };
          common = {
            name = "linux-headers-6.1.0-27-common_6.1.115-1_all.deb";
            sha256 = "0gyd1ajzns39dmj3mmgc3i3pafpsalb35aik6g5zmmkn1rk7k2yz";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.115-1_amd64.deb";
            sha256 = "0j9adaqinzvfb3rhqryljkalzj5xx4qpd66b673ibpigzq3jvjxv";
          };
          source = {
            name = "linux-source-6.1_6.1.115-1_all.deb";
            sha256 = "1d43xlzv4fnzlg62gxar36zxlxvvs2dkbpf8hq7s84gsgdmg38dy";
          };
        };
        patchelfInputs = [ elfutils ];
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
    Debian12_9 = {
      enabledForSDE = pkgs.lib.versionAtLeast version "9.11.0";
      kernelRelease = "6.1.0-29-amd64";
      stdenv = pkgs.gcc12Stdenv;
      buildTree = mkDebian {
        spec = {
          snapshotTimestamp = "20250120T023918Z";
          arch = {
            name = "linux-headers-6.1.0-29-amd64_6.1.123-1_amd64.deb";
            sha256 = "0zmqghr6g2sk8sbrdj0w84vhknnyxy1rxsf3hvb5vjhavmi394bz";
          };
          common = {
            name = "linux-headers-6.1.0-29-common_6.1.123-1_all.deb";
            sha256 = "0aak2wzj2fpz469z15sz520k8p4h2mi27zcfpirpxpm5libzfl6p";
          };
          kbuild = {
            name = "linux-kbuild-6.1_6.1.123-1_amd64.deb";
            sha256 = "0c5zbc69pj7qbgkbqacxh9j0562cbxri4vnrni3cfsapkvs8lqrh";
          };
          source = {
            name = "linux-source-6.1_6.1.123-1_all.deb";
            sha256 = "1lg8s38297lxwp0gk2mcyvkbflbdbjvcqw5yc7qn90ffpdm9d1bb";
          };
        };
        patchelfInputs = [ elfutils ];
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
          "9.11.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.1" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.11.2" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.12.0" = [ ./bf-drivers-kernel-9.12.patch ];
          "9.13.0" = [ ./bf-drivers-kernel-9.11.patch ];
          "9.13.1" = [ ./bf-drivers-kernel-9.13.1.patch ];
          "9.13.2" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.3" = [ ./bf-drivers-kernel-9.13.2.patch ];
          "9.13.4" = [ ./bf-drivers-kernel-9.13.2.patch ];
        };
      additionalModules = additionalModulesDebian11;
    };
  };
  kernelEnabled = _: spec:
    ! (spec.disable or false) &&
    (spec.enabledForSDE or true);
in
builtins.mapAttrs mkModules (lib.filterAttrs kernelEnabled kernels)
