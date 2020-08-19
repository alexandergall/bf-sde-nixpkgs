pkgs:

with pkgs;
let
  createEnvs = interp: modules:
    map (interp: interp.withPackages
          (ps: with ps;
	    map (name: ps.${name}) modules)
	) interp;
in [ getopt ] # [ getopt which sysctl utillinux ]
++ createEnvs [ python2 ] [ "grpcio" "jsonschema" "ipaddress" ]
#++ createEnvs [python2 python3]
#              [ "packaging" "jsl" "grpcio" "enum34" "protobuf"
#                "functools32" "jsonschema" "ipaddress" ]
