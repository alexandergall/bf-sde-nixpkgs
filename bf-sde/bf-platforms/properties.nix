## Definition of supported platforms and their properties.  Each
## platform must have a "baseboard" attribute with a value from the
## set of valid baseboard identifiers. It should also have a "target"
## attribute that specifies the P4 target to compile for when building
## a program for the platform.  The buildP4Program() support function
## uses this attribute by default.
##
## Additional attributes are ignored by the SDE package but may be
## used in other contexts, e.g. the serial* attributes are used by the
## ONIE installer from bf-sde/support/installers/onie.
let
  accton = {
    baseboard = "accton";
    target = "tofino";
    serialDevice = "ttyS0";
    serialSettings = "57600n8";
    mgmtEthPciAddr = "0000:02:00.0";
  };
in {
  ## This is a pseudo-platform which uses a variant of the reference
  ## BSP configured for the Tofino software model.
  model = {
    baseboard = "model";
    ## Can be overriden in the call of buildP4Program()
    target = "tofino";
  };
  ## Instead of using "model" and overriding the target in the call to
  ## buildP4Program(), one can use one of the following platforms to
  ## have the target selected automatically.
  modelT2 = {
    baseboard = "model";
    target = "tofino2";
  };
  modelT3 = {
    baseboard = "model";
    target = "tofino3";
  };
  accton_wedge100bf_32x = accton;
  accton_wedge100bf_32qs = accton;
  accton_wedge100bf_65x = accton;
  accton_as9516_32d = accton // {
    baseboard = "newport";
    target = "tofino2";
    mgmtEthPciAddr = "0000:08:00.0";
  };
  inventec_d5264q28b = {
    baseboard = "inventec";
    target = "tofino";
    serialDevice = "ttyS0";
    serialSettings = "115200n8";
    ## mgmtEthPciAddr TBD
  };
  inventec_d10064 = {
    baseboard = "inventec";
    target = "tofino";
    serialDevice = "ttyS0";
    serialSettings = "57600n8";
    mgmtEthPciAddr = "0000:02:00.0";
  };
  stordis_bf2556x_1t = {
    baseboard = "aps_bf2556";
    target = "tofino";
    serialDevice = "ttyS0";
    serialSettings = "115200n8";
    mgmtEthPciAddr = "0000:0a:00.0";
  };
  stordis_bf6064x_t = {
    baseboard = "aps_bf6064";
    target = "tofino";
    serialDevice = "ttyS0";
    serialSettings = "115200n8";
    ## mgmtEthPciAddr TBD
  };
}
