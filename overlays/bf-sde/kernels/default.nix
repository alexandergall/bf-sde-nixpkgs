pkgs:

with pkgs;
let
  uncompress = src:
    runCommand "kernel-config" {} ''
      gunzip ${src} -d -c >$out
    '';

  firstCharacterOf = string:
    builtins.substring 0 1 string;

  mkKernel = { id, version, localVersion, sha256 }:
      (callPackage (path + "/pkgs/os-specific/linux/kernel/manual-config.nix") {})
        {
          inherit version stdenv;
          configfile = uncompress (./. + "/${id}-kernel-config.gz");
          modDirVersion = "${version}${localVersion}";
          src = fetchurl {
            url = "mirror://kernel/linux/kernel/v${firstCharacterOf version}.x/linux-${version}.tar.xz";
            inherit sha256;
          };
          kernelPatches = [];
          config = { CONFIG_MODULES = "y"; };
        };

in builtins.foldl' (res: attrs: res // { "${attrs.id}" = mkKernel attrs; }) {} [
  ## sha256 hashes can be determined with
  ## nix-prefetch-url  http://cdn.kernel.org/pub/linux/kernel/v4.x/linux-<kernelVersion>.tar.xz 
  rec {
    id = "k4_14_151_ONL_7c3bfd";
    version = "4.14.151";
    localVersion = "-OpenNetworkLinux";
    sha256 = "1bizb1wwni5r4m5i0mrsqbc5qw73lwrfrdadm09vbfz9ir19qlgz";
  }
  rec {
    id = "k4_19_81_ONL_1537d8";
    version = "4.19.81";
    localVersion = "-OpenNetworkLinux";
    sha256 = "17g2wiaa7l7mxi72k79drxij2zqk3nsj8wi17bl4nfvb1ypc2gi9";
  }
]
