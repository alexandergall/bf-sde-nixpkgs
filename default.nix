{ overlays ? []
, nixpkgs ?
  fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/23.05-130-g70f7275b32f.tar.gz;
    sha256 = "08crz8z6jlvgk095pv70fix70ag9axy8qk46yhdal2kd9gvan8v0";
  }
,  ...
} @attrs:

import nixpkgs ( attrs // {
  overlays = (import ./overlay.nix) nixpkgs ++ overlays;
  config = {
    permittedInsecurePackages = [
      ## 23.05 is the first release that disables python2 by default.
      ## It's still there and as long as it works we raise it from the
      ## dead.
      "python-2.7.18.6"

      ## OpenSSL 1.1 will be EOL by the end of 2023 but we only use it
      ## to patch some binaries in the Debian kbuild environment
      "openssl-1.1.1v"
    ];
  };
})
