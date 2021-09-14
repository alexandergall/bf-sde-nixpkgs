## Definition of supported platforms and their properties.  Each
## platform must have a "baseboard" attribute with a value from the
## set of valid baseboard identifiers. Additional attributes are
## ignored by the SDE package but may be used in other contexts,
## e.g. the serial* attributes are used by the ONIE installer from
## bf-sde/support/installers/onie.
let
  accton = {
    baseboard = "accton";
    serialDevice = "ttyS0";
    serialSettings = "57600n8";
    mgmtEthPciAddr = "0000:02:00.0";
  };
in {
  ## This is a pseudo-platform which uses a variant of the reference
  ## BSP configured for the Tofino software model.
  model = {
    baseboard = "model";
  };
  accton_wedge100bf_32x = accton;
  accton_wedge100bf_32qs = accton;
  accton_wedge100bf_65x = accton;
  inventec_d5264q28b = {
    baseboard = "inventec";
    serialDevice = "ttyS0";
    serialSettings = "115200n8";
    ## mgmtEthPciAddr TBD
  };
  stordis_bf2556x_1t = {
    baseboard = "aps_bf2556";
    serialDevice = "ttyS0";
    serialSettings = "115200n8";
    mgmtEthPciAddr = "0000:0a:00.0";
  };
  stordis_bf6064x_t = {
    baseboard = "aps_bf6064";
    serialDevice = "ttyS0";
    serialSettings = "115200n8";
    ## mgmtEthPciAddr TBD
  };
}
