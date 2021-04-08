{ kernel-modules, lib, runCommandLocal, stdenv, runtimeShell }:

kernelRelease:

let
  envKernelID = builtins.getEnv "SDE_KERNEL_ID";
  matches = lib.filterAttrs (_: spec: spec.release == kernelRelease) kernel-modules;
  ids = lib.attrNames matches;
  nMatches = builtins.length ids;
in
  if envKernelID != "" then
    kernel-modules.${envKernelID} or (throw ("The SDE_KERNEL_ID environment variable " +
      "ist set to \"${envKernelID}\" but matches no supported kernel for " +
      "kernel release ${kernelRelease}"))
  else
    if nMatches == 0 then
      ## Unsupported kernel, create a dummy modules package which
      ## exits with an error when attempting to load a module.
      builtins.trace "Kernel ${kernelRelease} is not supported, bf_switchd on TNA not available"
      stdenv.mkDerivation {
        name = "bf-sde-unsupported-kernel";
        phases = [ "installPhase" ];
        installPhase = ''
            mkdir -p $out/bin
            for mod in kpkt kdrv knet; do
              load_cmd=$out/bin/bf_''${mod}_mod_load
              cat <<"EOF" >$load_cmd
            #!${runtimeShell}
            echo "No modules available for this kernel (${kernelRelease})"
            exit 1
            EOF
            chmod a+x $load_cmd
            cp $load_cmd $out/bin/bf_''${mod}_mod_unload
            done
        '';
      }
    else
      if nMatches == 1 then
        kernel-modules.${builtins.head ids}
      else
        throw ("Multiple matches exist for kernel ${kernelRelease}. " +
          "Chose one by setting SDE_KERNEL_ID to one of: ${lib.concatStringsSep ", " ids}")
