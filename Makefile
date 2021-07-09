.DEFAULT_GOAL = none
SHELL := /bin/bash
THIS_DIR := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

none:

clean:
	rm -rf result*

VERSION=latest
INPUT_FN=
PLATFORM=

NIX_PURE =
env:
	@platform_override=$(PLATFORM); \
	if [ -f /etc/machine.conf ]; then \
	  . /etc/machine.conf; \
	  platform=$$onie_machine; \
	fi; \
	platform=$${platform_override:-$$platform}; \
	if [ -z "$$platform" ]; then \
	  echo "Can't determine platform from /etc/machine.conf, using Tofino model"; \
	  platform=model; \
	fi; \
	nix-shell $(NIX_PURE) -I nixpkgs=$(THIS_DIR) -E "with import <nixpkgs> {}; bf-sde.$(VERSION).mkShell" \
	    --argstr kernelRelease $$(uname -r) --argstr platform $$platform \
	    $(if $(INPUT_FN),--arg inputFn "$(INPUT_FN)") || true

env-list-versions:
	@nix-instantiate  -I nixpkgs=$(THIS_DIR) --eval -E "with import <nixpkgs> {}; builtins.attrNames (lib.filterAttrs (n: v: lib.isDerivation v) bf-sde)"

env-pure: NIX_PURE = --pure
env-pure: env
