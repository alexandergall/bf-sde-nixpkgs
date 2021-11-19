.DEFAULT_GOAL = none
.ONESHELL:

NIX_PATH =

NIX_EVAL = nix-instantiate --eval -E

none:

clean:
	rm -rf result*

define check_version
	version=$(VERSION)
	if [ "$$version" = "latest" ]; then
	  version=$$($(NIX_EVAL) --json 'with import ./. {}; bf-sde.latest.version' | jq -r '.')
	fi
	$(NIX_EVAL) "with import ./. {}; bf-sde-has-version \"$$version\"" >/dev/null
	versionTr=v$$(echo $$version | tr \. _)
endef

VERSION = "latest"

install:
	@set -e
	$(check_version)
	if nix-env -q --installed | grep sde-env-$$version >/dev/null; then
	  echo "Version $$version is already installed"
	  exit 0
	fi
	nix-env -j auto -f . -A bf-sde.$$versionTr.envCommand -i --preserve-installed

install-all:
	@set -e
	for v in $$($(NIX_EVAL) --json 'with import ./. {}; bf-sde-versions' | jq -cr '.[]'); do
	  $(MAKE) install VERSION=$$v
	done

uninstall:
	@nix-env -e "sde-env"

list-versions:
	@$(NIX_EVAL) --json 'with import ./. {}; bf-sde-versions' | jq -cr '.[]'

## The purpose of the wrapper is to install the closure of the actual
## installer.  It needs to work on pure NixOS as well as hybrid
## systems using an arbitrary Linux distribution with nixpkgs
## installed.  It is assumed that /bin/sh exists everywhere and
## provides a basic bourne-type shell.  The id, tail and xz utilities
## are also assumed to be in PATH.  The nix-* commands are located in
## /run/current-system/sw/bin/ on NixOS and in
## /nix/var/nix/profiles/default/bin on hybrid systems.
standalone:
	@set -e
	$(check_version)
	path=$$(nix-build -j auto --no-out-link -A bf-sde.$$versionTr.envStandalone)
	dest=~/sde-env-$$version-standalone-installer
	cat <<EOF >$$dest
	#!/bin/sh
	set -e
	PATH=\$$PATH:/run/current-system/sw/bin/nix-store:/nix/var/nix/profiles/default/bin
	if [ \$$(id -u) != 0 ]; then
	  echo "Please run as root"
	  exit 1
	fi
	echo "Installing installer dependencies"
	tail -n+13 \$$0 | xz -d | nix-store --import
	echo "Executing $$path/installer.sh"
	$$path/installer.sh
	exit 0
	EOF
	echo "Creating installer closure"
	nix-store --export $$(nix-store -qR $$path) | xz -T0 >>$$dest
	chmod a+x $$dest
	echo "Created $$(realpath $$dest)"
