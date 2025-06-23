{ pname, version, src, patches, lib, buildSupport, stdenv, cmake,
  python, thrift, protobuf, grpc, target-syslibs, target-utils,
  bf-utils, libedit, boost,

## The runtime version of the package doesn't include the tools
## related to the PD API and doesn't include any header files
  runtime ? false }:

let
  bf-drivers = stdenv.mkDerivation {
    pname = pname + lib.optionalString runtime "-runtime";
    inherit version patches;
    src = buildSupport.fixupSrc {
      inherit src;
      cmakeRules = ''
        include_directories(include)
        include_directories(.)
      '';
    };
    nativeBuildInputs = [ cmake python.pkgs.wrapPython thrift  libedit boost ];
    buildInputs = [ python protobuf grpc target-syslibs target-utils bf-utils ];

    ## Runtime dependencies of the Python modules contained in this
    ## package, e.g. bfrt_grpc.
    propagatedBuildInputs = with python.pkgs; [ grpcio six ];

    outputs = [ "out" ] ++ lib.optional (! runtime) "dev";
    enableParallelBuilding = true;

    cmakeFlags = [
      "-DTHRIFT-DRIVER=ON"
      "-DGRPC=ON"
      "-DBFRT=ON"
      "-DPI=OFF"
      "-DP4RT=OFF"
      "-DBF-PYTHON=ON"
      ## Kernel mdules are built separately
      "-DKERNEL-MODULES=OFF"
    ];

    preConfigure = ''
      sed -i -e 's/emulatorflag \''${CMAKE_C_FLAGS}/emulatorflag "\''${CMAKE_C_FLAGS}"/' CMakeLists.txt
    '' +
    ## Don't install module load/unload scripts, they are part of the kernel
    ## module packages
    ''
      sed -i -e 's/^.*mod_.*load.*$//' CMakeLists.txt
    '' +
    ## Remove lines preceeding the #!. A copyright notice was placed
    ## there, probably by mistake.
    ''
      sed -i -e '/^#!/,$!d' pd_api_gen/split_pd_thrift.py
      sed -i -e '/^#!/,$!d' tools/bf_switchd_dev_status.py
    '' + lib.optionalString runtime
      ## See above
    ''
      sed -i -e 's/^.*pd_api_gen.*$//' CMakeLists.txt
    '';

    postInstall = ''
        sitePath=$out/lib/${python.libPrefix}/site-packages
      '' + (lib.optionalString (! runtime)
        ## Remove the included tenjin module. For some reason it
        ## causes "NameError: global name 'six' is not defined" when
        ## generate_tofino_pd is run.
        ''
          rm $sitePath/tofino_pd_api/tenjin.*
       '') +

    ## Link the directories in site-packages/tofino and
    ## site-packages/tofino_pd_api to site-packages. This allows
    ## importing those modules without having to add the tofino and
    ## tofino_pd_api directories to the search path. This should be
    ## fine as long as it doesn't create conflicts, which is currently
    ## not the case.
    ''
      for obj in $sitePath/tofino/* ${lib.optionalString (! runtime) "$sitePath/tofino_pd_api/*"}; do
        ln -sr $obj $sitePath
      done
      python -m compileall $sitePath
    '' + (lib.optionalString runtime
      ## The runtime version doesn't have a "dev" output.
      ''
        rm -rf $out/include
      '');

    ## Apart from Python modules, this package also provides a few
    ## Python scripts that need to be wrapped to find their
    ## dependencies. We have to do this manually because we're not
    ## using buildPythonApplication. There are 4 such objects.
    ##
    ## bin/{gencli,generate_tofino_pd}.py are themselves wrappers
    ## around like-named scripts in $sitePath/tofino_pd_api. They are
    ## wrapped with wrapPythonPrograms.
    ##
    ## $sitePath/p4testutils/bf_switchd_dev_status.py doesn't require
    ## any non-default modules. A patchShebangs suffices.
    ##
    ## $sitePath/bfrtcli.py is used to start a Python shell from
    ## bf_switchd via the Python C API, i.e. it is never executed by
    ## itself and doesn't need to be wrapped fully. We use
    ## patchPythonScript to only set the search path.
    ##
    ## wrapPythonPrograms and patchPythonScript use the modules
    ## specified in pythonPath. We set this to the union of all
    ## modules used by these scripts.
    pythonPath = with python.pkgs; [
      ## generate_tofino_pd, gencli
      tenjin six
      ## bfrtcli
      traitlets prompt_toolkit ipython tabulate netaddr
    ];
    postFixup = (lib.optionalString (! runtime) ''
      chmod a+x $out/bin/split_pd_thrift.py
      chmod a-x $sitePath/tofino_pd_api/{gencli.py,generate_tofino_pd.py}
    '') + ''
      sitePath=$out/lib/${python.libPrefix}/site-packages
      chmod a+x $sitePath/p4testutils/bf_switchd_dev_status.py
      patchShebangs $sitePath/p4testutils/
      wrapPythonPrograms
      patchPythonScript $sitePath/bfrtcli.py
      python -m compileall $sitePath
    '';
  };

## Turn the derivation into a Python Module, i.e. inject all Python
## modules referenced in propagatedBuildInputs into the environment of
## Python packages that declare bf-drivers as inputs.
in python.pkgs.toPythonModule bf-drivers
