{ pkgs }:

{
  ## A release is the union of the slices for all kernel modules and
  ## platforms.  The slices are collected in an attribute set whose
  ## names are the platform and kernel ID of each slice joined by "_".
  ## kernelModules must be a set like the value of
  ## ../kernels/default.nix, platforms must be a list of platform
  ## names from ../bf-platforms/properties.nix.
  mkRelease = slice: kernelModules: platforms:
    let
      namesFromAttrs = attrs:
        attrs.platform + "_" + attrs.kernelModules.kernelID;
    in
      builtins.foldl' (final: next:
        final // {
          ${namesFromAttrs next} = slice next.kernelModules next.platform;
        })
        {}
        (pkgs.lib.crossLists (platform: kernelModules: { inherit platform kernelModules; }) [
          platforms
          (builtins.attrValues kernelModules)
        ]);

  ## The closure of a release is the list of paths that needs to be
  ## available on a binary cache for pure binary deployments.  To
  ## satisfy restrictions imposed by Intel on the distribution of
  ## parts of the SDE as a runtime system, we set up a post-build hook
  ## on the Hydra CI system to copy these paths to a separate binary
  ## cache which can be made available to third parties. The hook uses
  ## the releaseClosure to find all paths from a single derivation. It
  ## is triggered by the name of that derivation, hence the override.
  mkReleaseClosure = release: name:
    (pkgs.closureInfo {
      rootPaths = with pkgs.lib; collect (set: isDerivation set) release;
    }).overrideAttrs (_: { name = "${name}-release-closure"; });
}
