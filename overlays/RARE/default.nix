{ bf-sde, callPackage }:

{
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
}
