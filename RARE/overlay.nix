let
  overlay = self: super:
    {
      freerouter = super.callPackage ./freerouter {};
      RARE = import ./RARE {
        bf-sde = self.bf-sde.v9_2_0.k4_19_81_ONL_1537d8;
        inherit (self) callPackage;
      };
    };
in [ overlay ]
