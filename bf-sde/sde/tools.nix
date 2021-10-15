{ src, patches, version, sdeEnv, runtime, baseboard, stdenv, lib,
  makeWrapper, python, coreutils, ethtool, iproute, utillinux,
  gnugrep, gnused, gawk, less, findutils, gcc, gnumake, which, procps,
  bash, cmake }:

stdenv.mkDerivation {
  inherit version src patches;
  pname = "bf-tools" + lib.optionalString runtime "-runtime";

  buildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin

    wrap () {
      chmod a+x $1
      wrapProgram $1 \
        --set SDE ${sdeEnv} --set SDE_INSTALL ${sdeEnv} \
        --set PATH $2 "''${@:3}"
    }

    copy () {
      cp $1 $out/bin/$2
      [ -n "$3" ] && wrap $out/bin/$2 $3
    }

    substitute run_switchd.sh $out/bin/run_switchd.sh \
      --replace sudo /usr/bin/sudo \
      --replace /usr/local/lib: ""
    wrap $out/bin/run_switchd.sh \
      "${lib.strings.makeBinPath [ coreutils utillinux findutils gnugrep gnused procps bash ]}"

    copy run_bfshell.sh run_bfshell.sh \
      "${lib.strings.makeBinPath [ coreutils utillinux ]}"

    '' + lib.optionalString (! runtime || baseboard == "model") ''

    substitute run_tofino_model.sh $out/bin/run_tofino_model.sh \
      --replace sudo /usr/bin/sudo \
      --replace /usr/local/lib: ""
    wrap $out/bin/run_tofino_model.sh \
      "${lib.strings.makeBinPath [ coreutils utillinux findutils ]}:/usr/bin"

    '' + lib.optionalString (! runtime) ''

    ## A test script could need additional Python modules at runtime.
    ## The bare ptf command has an option --pypath for this purpose,
    ## but it is hidden behind the run_p4_test.sh wrapper. We could
    ## simply set PYTHONPATH directly before running run_p4_test.sh,
    ## but this could interfere with other Python programs run in the
    ## same environment.  To isolate the additional modules, we use
    ## PTF_PYTHONPATH and translate it to PYTHONPATH in the wrapper.
    substitute run_p4_tests.sh $out/bin/run_p4_tests.sh --replace sudo /usr/bin/sudo
    chmod a+x $out/bin/run_p4_tests.sh
    wrap $out/bin/run_p4_tests.sh \
      "${lib.strings.makeBinPath [ coreutils utillinux gawk python ]}" \
      --run "export PYTHONPATH=\$PTF_PYTHONPATH:\$PYTHONPATH"

  '' + (if (lib.versionOlder version "9.7.0") then
          ''
            ## This script was copied from the tools provided for
            ## the BF Academy courses.
            copy ${./p4_build.sh} p4_build.sh \
              "${lib.strings.makeBinPath [ coreutils utillinux gnugrep gnused gawk
                                           less findutils gcc gnumake which python ]}"

          ''
        else
          ''
            copy ${./p4_build-cmake} p4_build.sh \
              "${lib.strings.makeBinPath [ sdeEnv coreutils utillinux cmake gnumake
                                           gcc findutils gnused python ]}"
          '');
}
