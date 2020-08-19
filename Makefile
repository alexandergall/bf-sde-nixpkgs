.DEFAULT_GOAL = none

none:

bf-sde-closure:
	nix-store --add-fixed sha256 bf-sde-build-inputs/*
	path=$$(nix-build --cores 0 -E 'with import ./nixpkgs.nix; bf-sde') ;\
	nix-store --export $$(nix-store -qR $$path) >$@

bf-sde-env:
	NIX_PATH=. nix-shell --pure --keep SDE --keep SDE_INSTALL --cores 0 ./environments/bf-sde/env.nix || true

bmv2-env:
	nix-shell --pure --cores 0 ./environments/bmv2/env.nix || true
