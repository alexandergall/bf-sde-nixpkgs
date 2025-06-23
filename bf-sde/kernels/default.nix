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

{ withAsic, bf-drivers-src, pkgs, version, callPackage, drvsWithKernelModules }:

with pkgs;

let
  mk = arg: pkg:
    let
      mkKbuild = callPackage ./make-kbuild.nix { inherit (arg) patchelfInputs; };
    in
      callPackage pkg (arg.spec // { inherit mkKbuild; });
  mkDebian = arg:
    mk arg ./debian.nix;
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

  ## Per-baseboard modules that are not included in the plain vanilla
  ## Debian kernels.
  additionalModulesDebian = {
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
  } // lib.optionalAttrs withAsic {
    Debian12_0 = {
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
        patchelfInputs = [ elfutils ];
      };
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_1 = {
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
        patchelfInputs = [ elfutils ];
      };
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_4 = {
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
        patchelfInputs = [ elfutils ];
      };
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_5 = {
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
        patchelfInputs = [ elfutils ];
      };
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_6 = {
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
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_7 = {
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
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_8 = {
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
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
    Debian12_9 = {
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
      patches = {
        "9.13.4" = [ ./bf-drivers-kernel.patch ];
      };
      additionalModules = additionalModulesDebian;
    };
  };
  kernelEnabled = _: spec:
    ! (spec.disable or false) &&
    (spec.enabledForSDE or true);
in
builtins.mapAttrs mkModules (lib.filterAttrs kernelEnabled kernels)
