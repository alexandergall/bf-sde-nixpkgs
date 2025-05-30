### Merge the open-source SDE with the elements of the closed-source
### SDE to provide the full functionality to run on actual
### hardware. Hopefully, this restriction will be removed in the
### future.

{ src, rdc, withAsic, runCommand }:

if withAsic
then
  runCommand "open-p4studio-asic" {} ''
    mkdir sde
    tar -C ${src} -cf - . | tar -C sde -xf -
    chmod -R u+rw sde
    mkdir rdc
    tar -xf ${rdc.src} --wildcards --strip-components=2 '*/packages/bf-drivers*'
    tar -C rdc -xf bf-drivers* --strip-components=1

    . sde/hw/rdc_setup.sh
    RDC_BFD=rdc
    OS_BFD=sde/pkgsrc/bf-drivers
    rdc_setup
    mkdir $out
    tar -C sde -cf - . | tar -C $out -xf -
  ''
else
  src
