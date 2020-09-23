{ fetchgit }:

{
  version = "20.6.23";
  src = fetchgit {
    url = "https://bitbucket.software.geant.org/scm/rare/rare.git";
    rev = "e2bece";
    sha256 = "1ys8i0g97i9fnc573bc4xkr9vz4g0aqwfc57qa7cvp78vlvax1x3";
  };
}
