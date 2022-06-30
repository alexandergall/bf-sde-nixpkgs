{ kernel-modules, lib, runCommandLocal, stdenv, runtimeShell }:

kernelRelease:

let
  envKernelID = builtins.getEnv "SDE_KERNEL_ID";
  matches = lib.filterAttrs (_: spec: spec.kernelRelease == kernelRelease) kernel-modules;
  ids = lib.attrNames matches;
  nMatches = builtins.length ids;
in
if envKernelID != "" then
  builtins.trace ("Using kernel ${envKernelID} from the environment, "
                  + "ignoring kernelRelease \"${kernelRelease}\"")
    kernel-modules.${envKernelID} or
    (throw ("The SDE_KERNEL_ID environment variable " +
            "ist set to \"${envKernelID}\" but matches no supported kernel"))
else
  if nMatches == 0 then
    throw "Unsupported kernel: ${kernelRelease}"
    #builtins.trace "Kernel ${kernelRelease} is not supported, bf_switchd on TNA not available"
    #  kernel-modules.none
  else
    if nMatches == 1 then
      kernel-modules.${builtins.head ids}
    else
      throw ("Multiple matches exist for kernel ${kernelRelease}. " +
             "Chose one by setting SDE_KERNEL_ID to one of: ${lib.concatStringsSep ", " ids}")
