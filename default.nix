{ overlays ? []
, nixpkgs ?
  fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/23.05-pre-39751-g44780192142.tar.gz;
    sha256 = "06xykb1b7wxryy05cm63dcxdik6z6zlq14qxvy0mkhpmjhlxa25w";
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
      "openssl-1.1.1t"
    ];
  };
})
