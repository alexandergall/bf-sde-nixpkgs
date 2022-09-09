{ ... }@args:

## Before SDE 9.9, the APS BSP supplied support for the bf2556 and the
## bf6064 patfroms and included the Marvell SAL
builtins.trace (builtins.concatStringsSep " " (builtins.attrNames args))import ./aps args
