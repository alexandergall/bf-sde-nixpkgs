{ bf-sde, fetchgit, flavor, buildFlags }:

bf-sde.buildP4Program rec {
  version = "20.6.23";
  name = "RARE${if flavor == null then "" else "-${flavor}"}-${version}";
  p4Name = "bf_router";
  path = "p4src";
  inherit buildFlags;

  src = fetchgit {
    url = "https://bitbucket.software.geant.org/scm/rare/rare.git";
    rev = "456648";
    sha256 = "1rnvkb5wkcxj7r918j7h8hjrys5c30rdn818bqfcksybg48x5wgi";
  };
}
