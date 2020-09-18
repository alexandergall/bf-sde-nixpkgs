{ stdenv, bf-sde, getopt, which, runtimeShell }:

{ name ? attrs.${name},
  version ? attrs.${version},
# The name of the p4 program to compile without the ".p4" extension
  p4Name ? attrs.${p4Name},
# The path to the program relative to the root of the source tree.
# I.e. the program to be compiled si expected to be
#   <path>/<p4Name>.p4
  path ? null,
# The flags passed to the p4_build.sh script
  buildFlags ? "",
  src ? attrs.${src},
} @attrs:

stdenv.mkDerivation rec {
  buildInputs = [ bf-sde getopt which ];

  inherit (attrs) name version src p4Name;
  
  buildPhase = ''
    set -e
    ## Create a copy of the SDE
    sde=$TEMP/bf-sde
    mkdir $sde
    tar -cf - -C ${bf-sde} . | tar -xf - -C $sde
    export SDE=$sde
    export SDE_INSTALL=$SDE/install
    find $sde -type d -exec chmod u+w {} \;
    touch $sde/stamp

    cmd="$sde/p4_build.sh ${buildFlags} ${if path == null then "." else path}/${p4Name}.p4"
    echo "Build command: $cmd"
    $cmd
  '';

  installPhase = ''
    mkdir $out
    cd $sde
    conf=$(find install/share/p4 -name ${p4Name}.conf)

    ## Copy build artefacts
    tar cf - --exclude=install/share/p4c $(find install/share -type f -cnewer stamp) | tar -xf - -C $out

    ## Create a configuration that references the build artefacts by
    ## absolute paths. This allows us to use the original SDE as a
    ## runtime system.
    cat $conf | sed -e "s,share/tofinopd,$out/install/share/tofinopd,g" > $out/${p4Name}.config

    ## Finally, this script will execute bf_switchd with our P4 program
    command=$out/bin/${p4Name}
    mkdir $out/bin
    echo '#!${runtimeShell}' > $command
    echo 'export SDE=${bf-sde}' >> $command
    echo 'export SDE_INSTALL=$SDE/install' >> $command
    echo "${bf-sde}/run_switchd.sh -p ${p4Name} -c $out/${p4Name}.config" >> $command
    chmod a+x $command

    ## Create links to bfshell and the kernel module load/unload scripts for convenience
    ln -s ${bf-sde}/install/bin/bfshell $out/bin
    for mod in kdrv knet kpkt; do
      name=bf_''${mod}_mod
      ln -s ${bf-sde}/install/bin/''${name}_unload $out/bin/''${name}_unload
      load=$out/bin/''${name}_load
      echo '#!${runtimeShell}' >>$load
      echo "${bf-sde}/install/bin/''${name}_load ${bf-sde}/install" >>$load
      chmod a+x $load
    done
  '';
}
