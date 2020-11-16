{ self, version, srcHash, bspHash, kernels, passthruFun,
  system, stdenv, writeText, gmp, glibc, python2, python3,
  pkg-config, file, thrift, openssl, boost, grpc,
  protobuf, zlib, libpcap, libusb, curl_7_52, cscope,
  runtimeShell
}:

let
    fixedDerivation = name: outputHash:
      builtins.derivation {
        inherit name outputHash;
        inherit system;
        builder = "none";
        outputHashMode = "flat";
        outputHashAlgo = "sha256";
      };
    src = fixedDerivation "bf-sde-${version}.tar" srcHash;
    bsp = fixedDerivation "bf-reference-bsp-${version}.tar" bspHash;
    passthru = passthruFun { inherit self; };

    profile = writeText "bf-studio-profile"
      ''
      # SDE_VERSION : ${version}
      custom_profile:
        # Global flags to configure
        global_configure_options: '''

        # SDE components to be installed
        packages:
          - bf-syslibs:
            - bf_syslibs_configure_options: '''
          - bf-utils:
            - bf_utils_configure_options: '''
          - bf-diags:
            - bf_diags_configure_options: "--with-libpcap=${libpcap}"
          - bf-drivers:
              - bf_drivers_configure_options: "--without-kdrv"
              - bf-runtime

        # Third party source packages to be installed
        package_dependencies:
          - grpc
          - thrift

        # Tofino architecture
        tofino_architecture: tofino
      '';

    ## Build- and run-time Python dependencies.  These environments
    ## contain the selected modules and a wrapper for the python2 and
    ## python3 interpreters that makes those modules available.
    ## PYTHONPATH would not work because it would mix up the modules
    ## for both interpreter versions.

    ## python2 is required by p4studio and the bfrt python API
    python2Env = python2.withPackages (ps: with ps;
      ## Build dependencies
      [ packaging pip pyyaml tenjin ] ++
      ## Run-time dependencies
      [ thrift grpcio ]);
    ## python3 is required by p4c
    python3Env = python3.withPackages (ps: with ps;
      [ packaging jsl jsonschema ]);

    kernelDevPaths = builtins.concatStringsSep " "
      (map (spec: spec.kernel.dev + ":" +
                  spec.version + spec.localVersion + ":" +
                  spec.distinguisher) kernels);

in stdenv.mkDerivation rec {
  inherit version src passthru;
  name = "bf-sde-${version}";

  outputs = [ "out" "support" ];

  ## We really only need python2Env as propagated input, but
  ## propagated inputs end up after regular inputs in the environment
  ## (e.g. PATH, PKG_CONFIG_PATH).  The problem is that we need to
  ## have python2 as the default python interpreter for all the
  ## stuff that simply uses "python".  Putting both environments
  ## into the propagated inputs (and keeping the order here) solves
  ## this problem.
  propagatedBuildInputs = [ python2Env python3Env ];
  buildInputs = [ pkg-config file thrift
                  openssl boost grpc protobuf zlib cscope
                  ## bf-diags
                  libpcap
                  ## bf-platforms
                  libusb curl_7_52 ] ++
                  (map (spec: spec.kernel.dev) kernels);

  patches = [ ./run_switchd.patch ];

  buildPhase = ''
    function fixup() {
      archive=$1
      dir=$(basename $archive .tgz)

      echo "Fixing up $archive"
      rm -rf $dir
      tar xf $1
      cd $dir

      while shift; do
        echo $1
        $1
      done

      for f in $(find . -type f -name configure); do
        if grep /usr/bin/file $f >/dev/null; then
          cmd="substituteInPlace $f --replace /usr/bin/file ${file}/bin/file"
          echo $cmd
          $cmd
        fi
      done

      patchShebangs .

      cd ..
      tar cf $archive $dir
      rm -rf $dir
    }

    function patchElf() {
      local archive=$1

      echo "Patching ELF dependencies in $archive"
      rm -rf tmp
      mkdir tmp
      cd tmp
      tar xf ../$1
      cd *

      for f in $(find . -type f -exec file {} \; | grep -i elf | cut -d' ' -f1 | sed -e 's/:$//'); do
        echo $f
        patchelf --set-interpreter ${glibc}/lib/ld-linux* $f || true
        case $f in
          *p4c-build-logs)
            patchelf --set-rpath ${zlib}/lib $f
            ;;
          *p4i-9.1.1-0.linux)
            patchelf --set-rpath ${stdenv.cc.cc.lib}/lib64 $f
            ;;
          *p4obfuscator)
            patchelf --set-rpath ${stdenv.cc.cc.lib}/lib64:${gmp}/lib $f
            ;;
        esac
      done

      for f in *; do
        if [[ $f =~ (.tar|.tgz) ]]; then
          patchElf $f
        fi
      done

      patchShebangs .

      cd ..
      tar cjf ../$archive *
      cd ..
      rm -rf tmp
    }

    function version() {
      printf "%02d%02d%02d" ''${1//./ }
    }

    fixup packages/bf-drivers-${version}.tgz \
      "patch -p1 -i ${./bf_switchd_model.patch}"
    fixup packages/bf-syslibs-${version}.tgz

    ## judy/libedit/klish (erroneously?) add $lt_sysroot to the
    ## include path, which results in a path with two leading
    ## slashes. The Nix gcc-wrapper considers this a "bad path" when
    ## $NIX_ENFORCE_PURITY is set, which is the case for nix-build but
    ## not fore nix-shell (even with the --pure flag)
    fixup packages/bf-utils-${version}.tgz \
      "substituteInPlace third-party/judy-1.0.5/configure --replace I\$lt_sysroot/ I" \
      "substituteInPlace third-party/libedit-3.1/configure --replace I\$lt_sysroot/ I" \
      "substituteInPlace third-party/klish/configure --replace I\$lt_sysroot/ I" \

    fixup packages/bf-diags-${version}.tgz \
      "substituteInPlace third-party/libcrafter/configure --replace withval/include/net/bpf.h withval/include/pcap.h" \
      "chmod u+x p4-build/tools/*.py"

    patchElf packages/p4-compilers-*
    patchElf packages/p4i-*
    patchElf packages/p4o-*

    mkdir -p $out/install
    export SDE=$(pwd)
    export SDE_INSTALL=$out
    
    pushd p4studio_build
    cp ${profile} profiles/custom_profile.yaml
    patchShebangs .

    ## sudo is not needed in the build environment
    substituteInPlace p4studio_build.py --replace sudo ""
    ## Pick up PKG_CONFIG_PATH from the build environment
    substituteInPlace p4studio_build.py --replace PKG_CONFIG_PATH= 'PKG_CONFIG_PATH=$PKG_CONFIG_PATH:'

    mkdir $TEMP/bsp
    tar xf ${bsp} -C $TEMP/bsp --strip-components 1

    if [ $(version ${version}) -ge $(version 9.2.0) ]; then
      extraOptions="--preserve_env"
      ## Starting with 9.2.0, studio ignores --skip-dependencies on non-ONL
      ## platforms to install GRCP and Protobuf dependencies.  It would
      ## probably be cleaner to add a section for NixOS in dependencies.yaml
      ## that specifies that nothing needs to be installed.
      substituteInPlace p4studio_build.py --replace "if params['skip_dependencies']:" "if False:"
    fi

    ## Starting with 9.3.0, the builder performs a "chdir ~", which
    ## fails in a pure build environment where HOME=/homeless-shelter
    HOME=/tmp
    ./p4studio_build.py -j4 --os-detail NixOS_19.03 --use-profile custom_profile \
      --bsp-path $TEMP/bsp --skip-os-check --skip-dependencies \
      --skip-kernelheader-check --skip-dependencies-check $extraOptions

    popd

    echo "Building kernel modules"
    pushd build/bf-drivers
    ../../pkgsrc/bf-drivers/configure --prefix=$SDE_INSTALL enable_thrift=no \
       enable_grpc=no enable_bfrt=no enable_p4rt=no enable_pi=no --with-kdrv=yes
    for spec in ${kernelDevPaths}; do
      IFS=":"
      set -- $spec
      path=$1
      version=$2
      distinguisher=$3
      IFS=" "

      echo "Kernel $version$distinguisher"
      export KDIR=$path/lib/modules/$version/build
      pushd kdrv
      make install

      mod_dir=$SDE_INSTALL/lib/modules/$version$distinguisher
      mkdir -p $mod_dir
      mv $SDE_INSTALL/lib/modules/*.ko $mod_dir

      make clean
      popd
    done
    popd
  '';

  installPhase = ''
    for mod in kpkt kdrv knet; do
      script=$SDE_INSTALL/bin/bf_''${mod}_mod_load
      substituteInPlace  $script \
        --replace lib/modules "lib/modules/\$(uname -r)\''${SDE_KERNEL_DISTINGUISHER:-}"
      mv $script ''${script}.wrapped
      echo '#!${runtimeShell}' >>$script
      echo "$script.wrapped $SDE_INSTALL" >>$script
      chmod a+x $script
    done
    tar -cf - bf-sde-${version}.manifest run_bfshell.sh run_switchd.sh run_tofino_model.sh | tar -xf - -C $out
    tar cf - pkgsrc/p4-build | tar -xf - -C $out
    tar cf - pkgsrc/p4-examples/tofino* | tar -xf - -C $out

    ## These scripts were copied from the tools provided for
    ## the BF Academy courses.
    cp ${./p4_build.sh} $out/bin/p4_build.sh
    cp ${./veth_setup.sh} $out/bin/veth_setup.sh
    cp ${./veth_teardown.sh} $out/bin/veth_teardown.sh
    mv run_*sh $out/bin
    chmod a+x $out/bin/*.sh

    ## The support output contains a script that starts a
    ## nix-shell in which P4 programs can be compiled and
    ## run in the context of the SDE
    mkdir -p $support/bin
    substitute ${./sde-env.sh} $support/bin/sde-env-${version} \
      --subst-var-by VERSION ${builtins.replaceStrings [ "." ] [ "_" ] version}
    chmod a+x $support/bin/sde-env-${version}
  '';
}
