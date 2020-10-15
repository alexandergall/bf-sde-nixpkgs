.DEFAULT_GOAL = none
SHELL := /bin/bash

none:

clean:
	rm -rf result*

VERSION="latest"
install: clean
	profile=$${SDE_PROFILE:-/nix/var/nix/profiles/per-user/$$USER/bf-sde}; \
	nixpkgs=$$(nix-store --add $$(realpath .)); \
	nix-env -p $$profile -i $$nixpkgs $$(nix-build build-support.nix --argstr version $(VERSION))

closures:
	export NIX_PATH=nixpkgs=.; \
	paths=$$(nix-build --cores 0 -A bf-sde); \
	for path in $$paths; do \
	  closure=$$(sed -e 's,.*-bf-sde-,,' <<< $$path).closure; \
	  echo "Creating $$closure"; \
	  nix-store --export $$(nix-store -qR $$path) >$$closure; \
	done
