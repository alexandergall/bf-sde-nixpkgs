{ fetchBitbucketPrivate }:

rec {
  version = "6c7abf";
  src = fetchBitbucketPrivate {
    url = "ssh://git@bitbucket.software.geant.org:7999/rare/rare-bf2556x-1t.git";
    rev = "${version}";
    sha256 = "16z96drd4hmhm2km7l662rz3z7gg1jnqkd272hvjn468yjc0l4n1";
  };
}
