let
  overlay = self: super:
    {
      dpdk = super.dpdk.overrideAttrs (oldAttrs: rec {
        version = "20.08";
        src = self.fetchurl {
          url = "https://fast.dpdk.org/rel/dpdk-${version}.tar.xz";
          sha256 = "0ixhb6jdjcn8191dk6g8dyby7qxwjfyj88r1vaimnp0vcl2gycqs";
        };
        MAKE_PAUSE = "n";
      });
      freerouter = super.callPackage ./freerouter {
        openssl = self.openssl_1_1;
      };
      RARE = import ./RARE {
        bf-sde = self.bf-sde.v9_2_0.k4_19_81_ONL_1537d8;
        inherit (self) callPackage;
      };
    };
in [ overlay ]
