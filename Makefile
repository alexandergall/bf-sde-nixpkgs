.DEFAULT_GOAL = none

none:

closures:
	export NIX_PATH=nixpkgs=.; \
	paths=$$(nix-build --cores 0 -A bf-sde); \
	for path in $$paths; do \
	  closure=$$(sed -e 's,.*-bf-sde-,,' <<< $$path).closure; \
	  echo "Creating $$closure"; \
	  nix-store --export $$(nix-store -qR $$path) >$$closure; \
	done

bf-sde-env:
	NIX_PATH=. nix-shell --pure --keep SDE --keep SDE_INSTALL --cores 0 ./environments/bf-sde/env.nix || true

bmv2-env:
	nix-shell --pure --cores 0 ./environments/bmv2/env.nix || true
