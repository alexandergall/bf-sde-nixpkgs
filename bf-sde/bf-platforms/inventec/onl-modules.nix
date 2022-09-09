{ lib, stdenv, kernelSpec ? null, fetchFromGitHub }:


if (kernelSpec == null) then
  stdenv.mkDerivation {
    name = "inventec-onl-kmod-dummy";
    phases = [ "installPhase" ];
    installPhase = ''
      touch $out
    '';
  }
else
  if (lib.versionOlder kernelSpec.kernelRelease "5.0") then
  stdenv.mkDerivation {
    name = "inventec-kmod-unsupported";
    phases = [ "installPhase" ];
    installPhase = ''
      dir=$out/lib/modules/${kernelSpec.kernelRelease}
      mkdir -p $dir
      touch $dir/.inventec-unsupported
    '';
  }
  else
    stdenv.mkDerivation rec {
      pname = "inventec-onl-kmod";
      version = "d3042a";
      patches = [ ./onl-modules.patch ];
      src = fetchFromGitHub {
        owner = "inventec-switches";
        repo = "inventec-onl";
        rev = "${version}";
        sha256 = "11hych5qm6slaisxm9a9iypkiqxidg2cf0hrm5almy5c6b5w2q8w";
      };
      buildPhase = ''
        sdir=$(realpath packages/platforms/inventec/x86-64/d5264q28b/modules/builds/src)
        make -C ${kernelSpec.buildTree} M=$sdir src=$sdir
      '';
      installPhase = ''
        dir=$out/lib/modules/${kernelSpec.kernelRelease}
        mkdir -p $dir
        cp $sdir/*.ko $dir
      '';
    }
