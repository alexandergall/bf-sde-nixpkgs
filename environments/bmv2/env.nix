with import ../../nixpkgs.nix;

stdenv.mkDerivation rec {
  name = "bmv2-environment";
  buildInputs = [
    bmv2 p4c dpkg ethtool gcc gnumake telnet killall jre patchelf
  ];
}
