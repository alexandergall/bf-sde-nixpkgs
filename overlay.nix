let
  grpc_1_17_0_attrs = super: pname: fetchSubmodules: sha256: rec {
    version = "1.17.0";
    name = "${pname}-${version}";
    src = super.fetchFromGitHub {
      owner = "grpc";
      repo = "grpc";
      rev = "v${version}";
      inherit fetchSubmodules sha256;
    };
    ## Fix issue with glibc 2.30 and later
    patches = [ ./grpc/1.17.0-glibc.patch ];
  };

  overlay = self: super: rec {
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

    thrift_0_12 = super.thrift.overrideAttrs(oldAttrs: rec {
      version = "0.12.0";
      name = "thrift-${version}";

      src = super.fetchurl {
          url = "https://archive.apache.org/dist/thrift/${version}/${name}.tar.gz";
          sha256 = "0a04v7dgm1qzgii7v0sisnljhxc9xpq2vxkka60scrdp6aahjdn3";
      };

    });

    thrift_0_13 = super.thrift.overrideAttrs(oldAttrs: rec {
      version = "0.13.0";
      name = "thrift-${version}";

      src = super.fetchurl {
          url = "https://archive.apache.org/dist/thrift/${version}/${name}.tar.gz";
          sha256 = "0yai9c3bdsrkkjshgim7zk0i7malwfprg00l9774dbrkh2w4ilvs";
      };

    });

    ## Override protobuf globally because grpc and grpcio depend on it and
    ## they are both dependencies of bf-drivers.
    protobuf = self.protobuf3_6;

    grpc = super.grpc.overrideAttrs(oldAttrs:
      (grpc_1_17_0_attrs super "grpc" false "17y8lhkx22qahjk89fa0bh76q76mk9vwza59wbwcpzmy0yhl2k23") // {
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

    python2 = super.python2.override {
      packageOverrides = python-self: python-super: {
        grpcio = python-super.grpcio.overrideAttrs(oldAttrs:
          grpc_1_17_0_attrs super "grpcio" true "06jpr27l71wz0fbifizdsalxvpraix7s5dg30pgd2wvd77ky5p3h");

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

        ply = python-super.ply.overrideAttrs (_: rec {
          pname = "ply";
          version = "3.9";

          src = python-super.fetchPypi {
            inherit pname version;
            sha256 = "0gpl0yli3w03ipyqfrp3w5nf0iawhsq65anf5wwm2wf5p502jzhd";
          };
        });

        ## Required by Intel's modified PTF from ptf-modules/bf-ptf
        scapy-helper = python-super.buildPythonPackage rec {
          pname = "scapy_helper";
          version = "0.10.0";

          buildInputs = with python-self; [ pyperclip scapy ];
          propagatedBuildInputs = with python-self; [ tabulate ];
          src = python-super.fetchPypi {
            inherit pname version;
            sha256 = "1xkmkb2vx2j5ca2367m1v4p821nnsm7rfxp621bbkxsav8kgc77g";
          };
        };
        pyperclip = python-super.pyperclip.overridePythonAttrs (_:  rec {
          pname = "pyperclip";
          version = "1.8.2";

          src = python-super.fetchPypi {
            inherit pname version;
            sha256 = "0mxzm43z2anr55gyz7awagvam4d5c2rlxhp9hjyg0d29n2l58lhh";
          };
        });
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

    ## This set contains one derivation per SDE version.  The names of
    ## the attributes are of the form "v<version>" with dots replaced
    ## by underscores, e.g. "v9_2_0".
    bf-sde = self.recurseIntoAttrs (import ./bf-sde { pkgs = self; });
  };
in [ overlay ]
