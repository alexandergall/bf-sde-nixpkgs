nixpkgsSrc:

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
  pythonCommon = super: python-self: python-super: {
    grpcio = python-super.grpcio.overrideAttrs (oldAttrs:
      grpc_1_17_0_attrs super "grpcio" true "06jpr27l71wz0fbifizdsalxvpraix7s5dg30pgd2wvd77ky5p3h");
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
      doCheck = false;
    };
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

    ## Used to compile the protobuf python bindings for the aps_bf2556 baseboard.
    grpcio-tools = python-super.grpcio-tools.overrideAttrs (oldAttrs: rec {
      version = "1.17.0";
      inherit (oldAttrs) pname;
      name = "${pname}-${version}";

      src = python-self.fetchPypi {
        inherit version pname;
        sha256 = "0qfjxvgk78w3m4wwk10qqkv027qhirrnc7c1dx41l1i1hwhws5wl";
      };
      enableParallelBuilding = ! python-self.isPy27;
      ## The tools are intended to be run as scripts. Make them executable so
      ## wrapPythonPrograms can find them.
      postInstall = ''
        chmod a+x $out/lib/${python-self.python.libPrefix}/site-packages/grpc_tools/*.py
      '';
      ## By default, only scripts in $out are wrapped.
      ## setuptools is needed by the grpc_tools scripts
      pythonPath = oldAttrs.propagatedBuildInputs ++ (with python-self; [ setuptools ]);
      postFixup = ''
        wrapPythonProgramsIn $out/lib/${python-self.python.libPrefix}/site-packages/grpc_tools "$out $pythonPath"
      '';
    });
  };

  overlay = self: super: rec {
    ## Utility function to allow overrides of packages that are built
    ## with nested calls to callPackage. In that case override() is
    ## only able to override callPackage itself at the top level. To
    ## propagate overrides further down we need to put them into a new
    ## scope and use that scope's callPackage in the override. See
    ## protobuf below for an example.
    callPackageOverride = attrs:
      let
        scope = self.lib.makeScope self.newScope (_: attrs);
      in { inherit (scope) callPackage; };
    ## Some libraries compiled with GCC 11 (default of Nixpkgs 22.05)
    ## don't link with code compiled with older GCCs. The symptom is
    ## that the symbol std::__throw_bad_array_new_length cannot be
    ## resolved. We re-build the affected libraries with GCC 10.
    gccOverride = self.gcc10Stdenv;
    ## Utility function to override thrift and it's boost dependency
    thriftOverride = thrift:
      thrift.override {
        stdenv = gccOverride;
        boost = self.boost.override (callPackageOverride {
          stdenv = gccOverride;
        });
      };

    ## Newer versions of curl don't understand the standard
    ## notation of IPv6 scope identifiers with link-local addresses
    ## as used by the bf-platforms SDE sub-package.  We don't override
    ## the standard package to avoid massive amounts of re-building of
    ## packages that depend on it.
    curl_7_52 = super.curl.overrideAttrs (oldAttrs: rec {
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
      doCheck = false;
    });

    thrift_0_12 = thriftOverride (super.thrift.overrideAttrs (oldAttrs: rec {
      version = "0.12.0";
      name = "thrift-${version}";

      src = super.fetchurl {
          url = "https://archive.apache.org/dist/thrift/${version}/${name}.tar.gz";
          sha256 = "0a04v7dgm1qzgii7v0sisnljhxc9xpq2vxkka60scrdp6aahjdn3";
      };
      doCheck = false;
    }));

    thrift_0_13 = thriftOverride (super.thrift.overrideAttrs (oldAttrs: rec {
      version = "0.13.0";
      name = "thrift-${version}";

      src = super.fetchurl {
          url = "https://archive.apache.org/dist/thrift/${version}/${name}.tar.gz";
          sha256 = "0yai9c3bdsrkkjshgim7zk0i7malwfprg00l9774dbrkh2w4ilvs";
      };
      doCheck = false;
    }));

    thrift_0_14 = thriftOverride (super.thrift.overrideAttrs (oldAttrs: rec {
      version = "0.14.0";
      name = "thrift-${version}";

      src = super.fetchurl {
          url = "https://archive.apache.org/dist/thrift/${version}/${name}.tar.gz";
          sha256 = "0wgzk2wcjmr01k719d9yw7qx7hwvhgjzcnyn7wd2wli667v69jwd";
      };
      patches = [];
      cmakeFlags = oldAttrs.cmakeFlags ++ [
        "-DBUILD_JAVASCRIPT:BOOL=OFF"
        "-DBUILD_NODEJS:BOOL=OFF"
      ];
      doCheck = false;
    }));

    ## Used to patch the tofino-model binary
    libcli1_10 = super.libcli.overrideAttrs (oldAttrs: rec {
      version = "1.10.0";
      src = self.fetchFromGitHub {
        sha256 = "0rhad7jk439nvj7rnf72bsa0kxbp449xy4ixhgz5y9j6s350jq64";
        rev = "v${version}";
        repo = "libcli";
        owner = "dparrish";
      };
      patches = [];
    });

    ## Override protobuf globally because grpc and grpcio depend on it and
    ## they are both dependencies of bf-drivers.
    protobuf = (super.protobuf.overrideAttrs (_: rec {
      version = "3.6.1.3";
      src = self.fetchFromGitHub {
        owner = "protocolbuffers";
        repo = "protobuf";
        rev = "v${version}";
        sha256 = "1spj0d4flx6h3phxx3sg9r00yv734hina3365avkcz9brnm089c1";
      };
    })).override (
      let
        stdenv = gccOverride;
        buildPackages = self.buildPackages // { inherit stdenv; };
      in callPackageOverride { inherit stdenv buildPackages; }
    );

    grpc = (super.grpc.overrideAttrs (oldAttrs:
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
    })).override { stdenv = gccOverride; };

    python2 = super.python2.override {
      packageOverrides = python-self: python-super:
        (pythonCommon super python-self python-super) // {
        scapy = python-super.scapy.override {
          withOptionalDeps = false;
          withCryptography = false;
          withPlottingSupport = false;
          withGraphicsSupport = false;
        };
        pyperclip = python-super.pyperclip.overridePythonAttrs (_:  rec {
          doCheck = false;
        });
        ply = python-super.ply.overrideAttrs (_: rec {
          pname = "ply";
          version = "3.9";

          src = python-super.fetchPypi {
            inherit pname version;
            sha256 = "0gpl0yli3w03ipyqfrp3w5nf0iawhsq65anf5wwm2wf5p502jzhd";
          };
        });
        mox = python-self.buildPythonPackage rec {
          pname = "mox";
          version = "0.5.3";
          src = self.fetchurl {
            url = "http://pymox.googlecode.com/files/${pname}-${version}.tar.gz";
            sha256 = "4d18a4577d14da13d032be21cbdfceed302171c275b72adaa4c5997d589a5030";
          };
          # error: invalid command 'test'
          doCheck = false;
        };
        protobuf = python-super.protobuf.overridePythonAttrs (old: {
          ## protoc hangs when compiling the unittest proto files :/
          preConfigure = ''
            sed -i -e '/GenerateUnittestProtos()$/d' setup.py
          '';
          postInstall = ''
            touch $out/lib/${self.python2.libPrefix}/site-packages/google/__init__.py
          '';
        });
      };
    };

    python3 = super.python3.override {
      packageOverrides = python-self: python-super:
        (pythonCommon super python-self python-super) // {
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
        protobuf = python-super.protobuf.overridePythonAttrs (_: {
          preBuild = ''
            sed -i -e 's/_2to3//' setup.py
          '';
        });
      };
    };

    ## This set contains one derivation per SDE version.  The names of
    ## the attributes are of the form "v<version>" with dots replaced
    ## by underscores, e.g. "v9_2_0".
    bf-sde = self.recurseIntoAttrs (import ./bf-sde {
      pkgs = self;
      inherit nixpkgsSrc;
    });
    ## Utility functions
    bf-sde-versions =
      with self.lib;
      with builtins;
      sort versionOlder
        (unique (map (sde: sde.version)
          (filter isDerivation (attrValues self.bf-sde))));
    bf-sde-has-version = version:
      assert self.lib.assertOneOf "version" version self.bf-sde-versions;
      true;
    bf-sde-foreach = f:
      with self.lib;
      with builtins;
      map (sde: f sde) (filter isDerivation (attrValues self.bf-sde));
  };

  ## This overlay is only used when building the BSP for the APS
  ## BF2556.  It creates a special version of grpc that includes a
  ## symlink for the so version of libgrpc++.so. This is needed by
  ## the autoPatchelfHook to resolv this dependency when patching
  ## the salRefApp binary.
  overlayAPS = self: super: {
    grpcForAPSSalRefApp = super.grpc.overrideAttrs (_: {
      postFixup = ''
        ln -sr $out/lib/libgrpc++.so $out/lib/libgrpc++.so.1
      '';
    });
    boost167 = super.boost166.overrideAttrs (_: rec {
      version = "1.67.0";
      src = self.fetchurl {
        url = "mirror://sourceforge/boost/boost_${builtins.replaceStrings ["."] ["_"] version}.tar.bz2";
        # SHA256 from http://www.boost.org/users/history/version_1_67_0.html
        sha256 = "2684c972994ee57fc5632e03bf044746f6eb45d4920c343937a465fd67a5adba";
      };
    });
  };
in [ overlay overlayAPS ]
