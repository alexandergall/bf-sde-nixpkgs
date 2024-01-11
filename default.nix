{ overlays ? []
, nixpkgs ?
  fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/23.11-1639-gc1be43e8e837.tar.gz;
    sha256 = "01g1lcpc281ba2dll1bkdxjn9w7dric0nk0zwm8dgrjxhad90zhb";
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
      "python-2.7.18.7"

      ## OpenSSL 1.1 will be EOL by the end of 2023 but we only use it
      ## to patch some binaries in the Debian kbuild environment
      "openssl-1.1.1w"
    ];
  };
})
