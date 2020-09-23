{ bf-sde, callPackage }:

let
  fetchBitbucketPrivate = callPackage ./fetchbitbucket {
    identityFile = ./bitbucket_deployment_rsa;
  };
in rec {
  mpls = callPackage ./generic.nix {
    inherit bf-sde;
    flavor = "mpls";
    buildFlags = "-DHAVE_MPLS";
  };
  mpls_wedge100bf32x = callPackage ./generic.nix {
    inherit bf-sde;
    flavor = "mpls_wedge100bf32x";
    buildFlags = "-DHAVE_MPLS -D_WEDGE100BF32X_";
  };
  srv6 = callPackage ./generic.nix {
    inherit bf-sde;
    flavor = "srv6";
    buildFlags = "-DHAVE_SRV6";
  };
  srv6_wedge100bf32x = callPackage ./generic.nix {
    inherit bf-sde;
    flavor = "srv6_wedge100bf32x";
    buildFlags = "-DHAVE_SRV6 -D_WEDGE100BF32X_";
  };
  bf_forwarder = callPackage ./bf_forwarder.nix {
    inherit bf-sde sal_modules;
  };
  sal_modules = callPackage ./sal/modules.nix {
    inherit fetchBitbucketPrivate;
  };
  sal_bf2556x = callPackage ./sal/bf2556x.nix {
    inherit fetchBitbucketPrivate sal_modules;
  };
}
