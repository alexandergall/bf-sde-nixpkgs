{ nixpkgs, p4lang-nixpkgs, withAsic}:

let
  overlay = final: prev: {
    ## The deboostrap wrapper in 24.11 is missing a dependency
    debootstrap =
      let
        version = final.lib.version;
        major = final.lib.versions.major version;
        minor = final.lib.versions.minor version;
      in prev.debootstrap.overrideAttrs (final.lib.optionalAttrs
        (major == "24" && minor == "11")
        {
          postInstall = ''
            sed -i -e 's!^\(export PATH.*$\)!\1:${final.util-linux}/bin!' $out/bin/debootstrap
          '';
        });
    ## For the tofino model binary
    libcli_1_10 = prev.libcli.overrideAttrs (oldAttrs: rec {
      version = "1.10.0";
      src = final.fetchFromGitHub {
        hash = "sha256-xGAJytBGJl/+gz0S3xMhd/UJlF7iOJuP3DYNMuVpCmY=";
        rev = "v${version}";
        repo = "libcli";
        owner = "dparrish";
      };
      patches = [];
      env.NIX_CFLAGS_COMPILE = oldAttrs.env.NIX_CFLAGS_COMPILE + " " + toString [
        "-Wno-error=array-bounds"
      ];
    });
    python311 = prev.python311.override {
      packageOverrides = python-final: python-prev: {

        ## tenjin.py is included in the bf-drivers packages and used by
        ## various utilities to generate program-dependent APIs. That
        ## version of tenjin appears to be a customization of Tenjin
        ## 1.1.1 that makes use of six but it doesn't work with the Nix
        ## build. It is replaced by the stock 1.1.1 version via this
        ## override.
        tenjin = python-prev.buildPythonPackage rec {
          pname = "Tenjin";
          version = "1.1.1";
          name = "${pname}-${version}";

          src = python-final.fetchPypi {
            inherit pname version;
            sha256 = "15s681770h7m9x29kvzrqwv20ncg3da3s9v225gmzz60wbrl9q55";
          };
        };

        ## Required by ptf-modules
        scapy-helper = python-prev.buildPythonPackage rec {
          pname = "scapy_helper";
          version = "0.14.8";

          buildInputs = with python-final; [ pyperclip scapy ];
          propagatedBuildInputs = with python-final; [ tabulate ];
          src = python-final.fetchPypi {
            inherit pname version;
            sha256 = "0q71fmibb1wfwbzkwymv306kd0s6r9pvp8225h1l4bqla5sbblz9";
          };
          doCheck = false;
          preConfigure = ''
        echo ${version} >VERSION
        sed -i -e 's/tabulate~=/tabulate>=/' setup.py
      '';
        };

        ## Required by p4-compilers
        jsl = python-prev.buildPythonPackage rec {
          pname = "jsl";
          version = "0.2.4";

          src = python-final.fetchPypi {
            inherit pname version;
            sha256 = "17f14h2aj05hcwc5p1600s5n33fhfsjig7id5gqhixbgdc8j29i2";
          };
          doCheck = false;
        };
      };
    };

    ### The SDE packages are collected by version number in this set
    bf-sde = final.recurseIntoAttrs (import ./bf-sde {
      pkgs = final;
      inherit nixpkgs p4lang-nixpkgs withAsic;
    });
    ## Utility functions
    bf-sde-versions =
      with final.lib;
      with builtins;
      sort versionOlder
        (unique (map (sde: sde.version)
          (filter isDerivation (attrValues final.bf-sde))));
    bf-sde-has-version = version:
      assert final.lib.assertOneOf "version" version final.bf-sde-versions;
      true;
    bf-sde-foreach = f:
      with final.lib;
      with builtins;
      map (sde: f sde) (filter isDerivation (attrValues final.bf-sde));
  };
in [ overlay ]
