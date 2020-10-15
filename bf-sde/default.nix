{ pkgs }:

with pkgs;

let
  passthruFun = { self }:
    {
      ## A function that compiles a given P4 program in the context of
      ## the SDE.
      buildP4Program = callPackage ./build-p4-program.nix {
        bf-sde = self;
      };

      ## A function that can be used with nix-shell to create an
      ## environment for developing data-plane and control-plane
      ## programs in the context of the SDE (see ./sde-env.sh).  The
      ## function takes an optional argument which must be a function
      ## that is called with the package set and returns a list of
      ## of packages to be included in the environment.
      mkShell = { inputFn ? { pkgs }: [] }:
        let
          inputs = (builtins.tryEval inputFn).value { inherit pkgs; };
        in mkShell {
          ## kmod provides insmod, procps provides sysctl
          buildInputs = [ self kmod procps ] ++ inputs;
          shellHook = ''
            export P4_INSTALL=~/.bf-sde/${self.version}
            export SDE=${self}
            export SDE_INSTALL=${self}
            export SDE_BUILD=$P4_INSTALL/build
            export SDE_LOGS=$P4_INSTALL/logs
            export PYTHONPATH=${self}/lib/python2.7/site-packages/tofino:$PYTHONPATH
            mkdir -p $P4_INSTALL $SDE_BUILD $SDE_LOGS

            cat <<EOF

            Barefoot SDE ${self.version}

            Load/unload kernel modules: $ sudo bf_{kdrv,kpkt,knet}_mod_{load,unload}

            Compile: $ p4_build.sh <p4name>.p4
            Run:     $ run_switchd -p <p4name>
            Run Tofino model:
                     $ sudo veth_setup.sh
                     $ run_tofino_model -p <p4name>
                     $ run_switchd -p <p4name> -- --model

            Build artefacts and logs are stored in $P4_INSTALL

            Use "exit" or CTRL-D to exit this shell.

            EOF
            PS1="\n\[\033[1;32m\][nix-shell(\033[31mSDE-${self.version}\033[1;32m):\w]\$\[\033[0m\] "
          '';
        };
    };
  kernels = import ./kernels pkgs;
  mkSDE = sdeDef:
    let
      self = callPackage ./generic.nix ({
        inherit self kernels;
      } // sdeDef);
    in self;

  ## Download bf-sde-${version}.tar and bf-reference-bsp-${version}.tar
  ## from the BF FORUM repository and add them manually to the Nix store
  ##   nix-store --add-fixed sha256 <...>
  ## The hashes below are the "sha256sum" of these files.
  bf-sde = lib.mapAttrs (n: sdeDef: mkSDE (sdeDef // { inherit passthruFun; })) {
    v9_1_1 = {
      version = "9.1.1";
      srcHash = "be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11";
      bspHash = "aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8";
    };
    v9_2_0 = {
      version = "9.2.0";
      srcHash = "94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26";
      bspHash = "d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac";
    };
  };

in bf-sde // { latest = bf-sde.v9_2_0; }
