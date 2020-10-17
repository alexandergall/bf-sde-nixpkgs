.DEFAULT_GOAL = none
SHELL := /bin/bash
THIS_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

none:

clean:
	rm -rf result*

VERSION=latest
INPUT_FN=

install: clean
	profile=$${SDE_PROFILE:-/nix/var/nix/profiles/per-user/$$USER/bf-sde}; \
	nixpkgs=$$(nix-store --add $$(realpath .)); \
	nix-env -p $$profile -i $$nixpkgs $$(nix-build build-support.nix --argstr version "$(VERSION)")

env:
	nix-shell -I nixpkgs=$(THIS_DIR) -E "with import <nixpkgs> {}; bf-sde.$(VERSION).mkShell" $(if $(INPUT_FN),--arg inputFn "$(INPUT_FN)")

closures:
export NIX_PATH=nixpkgs=.; \
	paths=$$(nix-build --cores 0 -A bf-sde); \
	for path in $$paths; do \
	  closure=$$(sed -e 's,.*-bf-sde-,,' <<< $$path).closure; \
	  echo "Creating $$closure"; \
	  nix-store --export $$(nix-store -qR $$path) >$$closure; \
	done
