{ kernelRelease, runtimeShell, kmod, coreutils }:

''
  wrap () {
  cat <<EOF >> $1
  #!${runtimeShell}
  kernelRelease=\$(${coreutils}/bin/uname -r)
  if [ \$kernelRelease != ${kernelRelease} ]; then
    echo "\$0: expecting kernel ${kernelRelease}, got \$kernelRelease, aborting"
    exit 1
  fi
  exec $1.wrapped $out
  EOF
  }

  for script in $out/bin/*_mod_load; do
    echo "Fixing up $script"
    substituteInPlace  $script \
      --replace lib/modules "lib/modules/\$(${coreutils}/bin/uname -r)" \
      --replace insmod ${kmod}/bin/insmod
    mv $script ''${script}.wrapped
    wrap $script
    chmod a+x $script
  done
  for script in $out/bin/*_mod_unload; do
    echo "Fixing up $script"
    substituteInPlace $script \
      --replace rmmod ${kmod}/bin/rmmod
  done
''
