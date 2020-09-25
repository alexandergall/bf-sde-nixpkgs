pkgs:

with pkgs;
let
  uncompress = src:
    runCommand "kernel-config" {} ''
      gunzip ${src} -d -c >$out
    '';

  firstCharacterOf = string:
    builtins.substring 0 1 string;

  mkKernel = spec:
    let
      kernel = with spec; (callPackage (path + "/pkgs/os-specific/linux/kernel/manual-config.nix") {})
        rec {
          inherit version stdenv;
          modDirVersion = "${version}${localVersion}";
          configfile = uncompress (./. + "/${modDirVersion}${distinguisher}-kernel-config.gz");
          src = fetchurl {
            url = "mirror://kernel/linux/kernel/v${firstCharacterOf version}.x/linux-${version}.tar.xz";
            inherit sha256;
          };
          kernelPatches = [];
          config = { CONFIG_MODULES = "y"; };
        };
    in spec // { inherit kernel; };

in map mkKernel [
  {
    version = "4.14.151";
    localVersion = "-OpenNetworkLinux";
    distinguisher = "";
    sha256 = "1bizb1wwni5r4m5i0mrsqbc5qw73lwrfrdadm09vbfz9ir19qlgz";
  }
  {
    version = "4.19.81";
    localVersion = "-OpenNetworkLinux";
    distinguisher = "";
    sha256 = "17g2wiaa7l7mxi72k79drxij2zqk3nsj8wi17bl4nfvb1ypc2gi9";
  }
]
