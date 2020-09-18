{ stdenv, fetchFromGitHub, jdk, jre_headless, makeWrapper }:

stdenv.mkDerivation rec {
  name = "freerouter-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "mc36";
    repo = "freerouter";
    rev = "7b76f17";
    sha256 = "1m9h1xzmp7brp6srzwa4di15mb0azbsly6jaxqqfyna04y4bwdf7";
  };

  buildInputs = [ jdk jre_headless makeWrapper];

  buildPhase = ''
    ## We probably don't need the native stuff
    #mkdir binTmp
    #pushd misc/native
    #./c.sh
    #popd
    pushd src
    javac router.java
  '';

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/java

    jar cf $out/share/java/freerouter.jar router.class */*.class
    makeWrapper ${jre_headless}/bin/java $out/bin/freerouter \
      --add-flags "-cp $out/share/java/freerouter.jar router"
  '';

}
