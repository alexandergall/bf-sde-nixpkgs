{ kernel, path, stdenv, callPackage, runCommand, fetchurl, buildPackages }:

let
  uncompress = src:
    runCommand "kernel-config" {} ''
      gunzip ${src} -d -c >$out
    '';

  firstCharacterOf = string:
    builtins.substring 0 1 string;

  modDirVersion = "${kernel.version}${kernel.localVersion}";

  kernelDrv = (callPackage (path + "/pkgs/os-specific/linux/kernel/manual-config.nix") {})
    rec {
      inherit (kernel) version;
      inherit stdenv modDirVersion;
      configfile = uncompress kernel.config;
      src = fetchurl {
        url = if builtins.hasAttr "url" kernel
	  then
	    kernel.url
	  else
	    "mirror://kernel/linux/kernel/v${firstCharacterOf kernel.version}.x/linux-${kernel.version}.tar.xz";
        inherit (kernel) sha256;
      };
      kernelPatches = [];
      config = { CONFIG_MODULES = "y"; };
    };

in kernelDrv.overrideAttrs (oldAttrs: rec {

  ## The derivation from manual-config.nix doesn't work for newer
  ## kernels due to a space optimization applied in postInstall:
  ##
  ##    # To save space, exclude a bunch of unneeded stuff when copying.
  ##    (cd .. && rsync --archive --prune-empty-dirs \
  ##        --exclude='/build/' \
  ##        --exclude='/Documentation/' \
  ##        * $dev/lib/modules/${modDirVersion}/source/)
  ##
  ## Newer kernels require the Documentation directory to be present
  ## for the final steps of the kernel generation. The sole purpose
  ## of this override is to get rid of --exclude='/Documentation/'.
  ## This is essentially a copy of the original postInstall with
  ## that line removed.
  ##
  ## This override can be removed once nixpkgs has been upgraded to
  ## 19.09 or higher.

  postInstall =  ''
    mkdir -p $dev
    cp vmlinux $dev/
    if [ -z "$dontStrip" ]; then
      installFlagsArray+=("INSTALL_MOD_STRIP=1")
    fi
    make modules_install $makeFlags "''${makeFlagsArray[@]}" \
      $installFlags "''${installFlagsArray[@]}"
    unlink $out/lib/modules/${modDirVersion}/build
    unlink $out/lib/modules/${modDirVersion}/source

    mkdir -p $dev/lib/modules/${modDirVersion}/{build,source}

    # To save space, exclude a bunch of unneeded stuff when copying.
    (cd .. && rsync --archive --prune-empty-dirs \
        --exclude='/build/' \
        * $dev/lib/modules/${modDirVersion}/source/)

    cd $dev/lib/modules/${modDirVersion}/source

    cp $buildRoot/{.config,Module.symvers} $dev/lib/modules/${modDirVersion}/build
    make modules_prepare $makeFlags "''${makeFlagsArray[@]}" O=$dev/lib/modules/${modDirVersion}/build

    # Keep some extra files on some arches (powerpc, aarch64)
    for f in arch/powerpc/lib/crtsavres.o arch/arm64/kernel/ftrace-mod.o; do
      if [ -f "$buildRoot/$f" ]; then
        cp $buildRoot/$f $dev/lib/modules/${modDirVersion}/build/$f
      fi
    done

    # !!! No documentation on how much of the source tree must be kept
    # If/when kernel builds fail due to missing files, you can add
    # them here. Note that we may see packages requiring headers
    # from drivers/ in the future; it adds 50M to keep all of its
    # headers on 3.10 though.

    chmod u+w -R ..
    arch=$(cd $dev/lib/modules/${modDirVersion}/build/arch; ls)

    # Remove unused arches
    for d in $(cd arch/; ls); do
      if [ "$d" = "$arch" ]; then continue; fi
      if [ "$arch" = arm64 ] && [ "$d" = arm ]; then continue; fi
      rm -rf arch/$d
    done

    # Remove all driver-specific code (50M of which is headers)
    rm -fR drivers

    # Keep all headers
    find .  -type f -name '*.h' -print0 | xargs -0 chmod u-w

    # Keep linker scripts (they are required for out-of-tree modules on aarch64)
    find .  -type f -name '*.lds' -print0 | xargs -0 chmod u-w

    # Keep root and arch-specific Makefiles
    chmod u-w Makefile
    chmod u-w arch/$arch/Makefile*

    # Keep whole scripts dir
    chmod u-w -R scripts

    # Delete everything not kept
    find . -type f -perm -u=w -print0 | xargs -0 rm

    # Delete empty directories
    find -empty -type d -delete

    # Remove reference to kmod
    sed -i Makefile -e 's|= ${buildPackages.kmod}/bin/depmod|= depmod|'
  '';
})
