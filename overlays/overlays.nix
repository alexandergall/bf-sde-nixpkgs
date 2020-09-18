let
  grpc_1_17_0 = super: pname: fetchSubmodules: sha256: rec {
    version = "1.17.0";
    name = "${pname}-${version}";
    src = super.fetchFromGitHub {
      owner = "grpc";
      repo = "grpc";
      rev = "v${version}";
      inherit fetchSubmodules sha256;
    };
  };

  overlay = self: super:
    rec {
      ## Newer versions of curl don't understand the standard
      ## notation of IPv6 scope identifiers with link-local addresses
      ## as used by the bf-platforms SDE sub-package.  We don't override
      ## the standard package to avoid massive amounts of re-building of
      ## packages that depend on it.
      curl_7_52 = super.curl.overrideAttrs(oldAttrs: rec {
        name = "curl-7.52.0";
        ## fetchurlBoot is needed to break a dependency cycle with zlib
        src = self.stdenv.fetchurlBoot {
          urls = [
            "https://curl.haxx.se/download/${name}.tar.bz2"
            "https://github.com/curl/curl/releases/download/${self.lib.replaceStrings ["."] ["_"] name}/${name}.tar.bz2"
          ];
          sha256 = "1ijwvzi99nzc1ghc04d01ram674yaphj11srhjnpbsw58y5y38mr";
        };
        patches = [];
      });

      libpcap_1_8 = super.libpcap.overrideAttrs(oldAttrs: rec {
        version = "1.8";
        name = "libpcap-${version}";
      });

      ## Make the default explicit for future upgrades of the
      ## underlying nixpkgs
      protobuf = self.protobuf3_6;

      grpc = super.grpc.overrideAttrs(oldAttrs:
        (grpc_1_17_0 super "grpc" false "17y8lhkx22qahjk89fa0bh76q76mk9vwza59wbwcpzmy0yhl2k23") // {
        # grpc has a CMakefile and a standard (non-autoconf) Makefile. We
        # use cmake to build the package but that method does not support
        # pkg-config. We have to use the Makefile for that explicitely.
        postInstall = ''
            cd ..
            export BUILDDIR_ABSOLUTE=$out prefix=$out
            make install-pkg-config_c
            make install-pkg-config_cxx
        '';
      });

      thrift = super.thrift.overrideAttrs(oldAttrs: rec {
        version = "0.12.0";
        name = "thrift-${version}";

        src = super.fetchurl {
            url = "https://archive.apache.org/dist/thrift/${version}/${name}.tar.gz";
            sha256 = "0a04v7dgm1qzgii7v0sisnljhxc9xpq2vxkka60scrdp6aahjdn3";
        };

      });

      python2 = super.python2.override {
        packageOverrides = python-self: python-super: {
          grpcio = python-super.grpcio.overrideAttrs(oldAttrs:
	    grpc_1_17_0 super "grpcio" true "06jpr27l71wz0fbifizdsalxvpraix7s5dg30pgd2wvd77ky5p3h");

          ## tenjin.py is included in the bf-drivers packages and
          ## installed in
          ## SDE_INSTALL/lib/python2.7/site-packages/tofino_pd_api/.
          ## The module is used to build bf-diags, but it appears to
          ## have a bug which causes the build to fail. Inspection of
          ## a working build environment on ONL reveals that the
          ## module is actually overridden by tenjin from
          ## /usr/local/lib. We do the same here.
          tenjin = python-super.buildPythonPackage rec {
            pname = "Tenjin";
            version = "1.1.1";
            name = "${pname}-${version}";

            src = python-super.fetchPypi {
              inherit pname version;
              sha256 = "15s681770h7m9x29kvzrqwv20ncg3da3s9v225gmzz60wbrl9q55";
            };
          };

        };
      };

      python3 = super.python3.override {
        packageOverrides = python-self: python-super: {
          jsl = python-super.buildPythonPackage rec {
            pname = "jsl";
            version = "0.2.4";
            name = "${pname}-${version}";

            src = python-super.fetchPypi {
              inherit pname version;
              sha256 = "17f14h2aj05hcwc5p1600s5n33fhfsjig7id5gqhixbgdc8j29i2";
            };

            doCheck = false;
          };
        };
      };

      ## This is a set containing sets of derivations for
      ## each version of the SDE.  The names in this set are
      ## of the form "v<version>", e.g. "v9_2_0".  There is one
      ## derivation for each kernel defined in
      ## ./bf-sde/kernels/default.nix. The names of these derivations
      ## are given by the "id" attribute of the kernel, e.g.
      ##
      ##   bf-sde.v9_2_0.k4_14_151_ONL_7c3bfd
      ##
      ## Derivations within bf-sde will be built recursively.
      bf-sde = self.recurseIntoAttrs (import ./bf-sde { pkgs = self; });
      bf-sde-latest = bf-sde.v9_2_0;
      RARE = super.callPackage ./RARE { bf-sde = bf-sde.v9_2_0.k4_14_151_ONL_7c3bfd; };
    };
in [ overlay ]
