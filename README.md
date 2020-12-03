# bf-sde-nixpkgs

Nix packaging of the Barefoot SDE.

Note: The SDE for the Tofino series of programmable NPUs is currently
only available under NDA from Intel/Barefoot.  The users of this
repositories are assumed to be authorized to download and use the SDE.

In its current form (version 9.3.0 at the time of writing), the SDE
officially supports only a very specific set of operating systems.
The main reason for this restriction is the management of build- and
run-time dependencies.  Packaging of the SDE with Nix removes these
restrictions completely and makes it possible to install any version
of the SDE on any system that supports the Nix package manager itself,
including systems without Tofino ASIC, in which case P4 programs can
be executed on the Tofino software emulation.  Different versions of
the SDE can coexist on the same system.

The [first part](#part1) of this documentation provides a step-by-step
description of how to build and use the packages for developing P4
programs and their control-planes.  The [second part](#part2)
describes how to build packages for P4 applications using the SDE as a
run-time environment.

The [third part](#part3) provides some basic information about the Nix
package manager for novice users.  It also describes some technical
details of the SDE package regarding support for Linux kernels.

The `master` branch contains the current development code. Stable
releases are contained in the `release` branch and tagged with
`v<version>`.

Additional branches make use of the SDE as a run-time environment for
Tofino-based networking applications on production systems.

As a prerequisite for working with this Git repository, the following
steps must be completed first.

### Install the Nix package manager in multi-user mode

As a regular user, execute (or download and verify the script if you
don't trust the site)

```
$ bash <(curl -L https://nixos.org/nix/install) --daemon
```

and proceed as instructed.  This should work on any Linux distribution
because no support of the native package manager is required for the
installation.

### Clone into the repository

```
$ git clone --branch <tag> --recursive --shallow-submodules <...>
```

Replace `<tag>` with the desired release tag, e.g. `v1`.  This also
clones the `nixpkgs` Git sub-module.

### Fetch and verify source archives

Download the `bf-sde` and `bf-reference-bsp` archives for the desired
version of the SDE from the Intel website (requires registration and
NDA). Please verify that the `sha256` sums are as follows

| File  | sha256 |
| ------|--------|
| bf-sde-9.1.1.tar | `be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11` |
| bf-sde-9.2.0.tar | `94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26` |
| bf-sde-9.3.0.tgz | `566994d074ba93908307890761f8d14b4e22fb8759085da3d71c7a2f820fe2ec` |
| bf-reference-bsp-9.1.1.tar | `aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8` |
| bf-reference-bsp-9.2.0.tar | `d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac` |
| bf-reference-bsp-9.3.0.tgz | `dd5e51aebd836bd63d0d7c37400e995fb6b1e3650ef08014a164124ba44e6a06` |

### Add archives to the Nix store

Execute (as any user)

```
$ nix-store --add-fixed sha256 <bf-sde-archive> <bf-reference-bsp-archive>
```

Note that the suffixes of the files differ between releases.  The
names are exactly as they appear on the download site.

If this step is omitted, the build will fail with a somewhat cryptic
error similar to the following

```
while setting up the build environment: executing 'none': No such file or directory
builder for '/nix/store/fbycbaqb8l502pdwidjhipmd6b6ym6n1-bf-reference-bsp-9.2.0.tar.drv' failed with exit code 1
cannot build derivation '/nix/store/38s8lsm2f7vg93f7n5x98hwbzmdlxfq8-bf-sde-9.2.0.drv': 1 dependencies couldn't be built
error: build of '/nix/store/38s8lsm2f7vg93f7n5x98hwbzmdlxfq8-bf-sde-9.2.0.drv' failed
```

The `nix-store --add-fixed` command prints the name of the resulting
path in the Nix store, e.g.

```
$ nix-store --add-fixed sha256 bf-sde-9.3.0.tgz bf-reference-bsp-9.3.0.tgz
/nix/store/2bvvrxg0msqacn4i6v7fydpw07d4jbzj-bf-sde-9.3.0.tgz
/nix/store/4kiww8687ryxmx1xymi5rn5199yr5alj-bf-reference-bsp-9.3.0.tgz
```

As with any path in `/nix/store`, these objects can only be deleted
with `nix-store --delete <path>`, provided they are not referenced by
any other object in `/nix/store` (in that case the command will fail).

More information on the Nix store can be found [below](#nix-store).

## <a name="part1"></a>Part 1:  P4 Program Development

In this mode, the SDE is used as an actual development system, in
which the user can freely compile and run P4 programs as well as any
control-plane related code.  Multiple versions of the SDE are
supported on the same system concurrently.

The main feature of the SDE package with respect to development is the
ability to launch a shell within the environment of a particular
version of the SDE.

### Usage from a Repository Checkout

One way to launch the shell is to enter the top-level directory of the
repository and execute `make env`:

```
$ make env
nix-shell  -I nixpkgs=/home/gall/bf-sde-nixpkgs/ -E "with import <nixpkgs> {}; bf-sde.latest.mkShell"  || true

Barefoot SDE 9.2.0

Load/unload kernel modules: $ sudo bf_{kdrv,kpkt,knet}_mod_{load,unload}

Compile: $ p4_build.sh <p4name>.p4
Run:     $ run_switchd -p <p4name>
Run Tofino model:
         $ sudo veth_setup.sh
         $ run_tofino_model -p <p4name>
         $ run_switchd -p <p4name> -- --model

Build artefacts and logs are stored in /home/gall/.bf-sde/9.2.0

Use "exit" or CTRL-D to exit this shell.


[nix-shell(SDE-9.2.0):~/bf-sde-nixpkgs]$ 
```

When executed for the first time, this will build all packges from
source (or copy them from a binary cache), which may take up to 45
minutes, depending on the system. The resulting shell makes the
commands from the latest version of the SDE (9.2.0 in this case)
available through the user's `PATH`.  The introductory text summarizes
how to compile and run a P4 program.

(TBD: Describe all commands and their usage)

The `make` command is equivalent to

```
$ make env VERSION=latest
```

To select a particular version, use

```
$ make env VERSION=<version>
```

where `<version>` can be any of the values listed by `make env-list-versions`, currently

```
$ make env-list-versions
[ "latest" "v9_1_1" "v9_2_0" "v9_3_0"]
```

### Usage from a Nix Profile

Instead of keeping a copy of the Git repository around and using
`make` to launch a shell, it is also possible to install the SDE in a
[Nix profile](https://nixos.org/manual/nix/stable/#sec-profiles) by
executing

```
$ make install-sde
```

in the top-level directory of the repository.  This performs the
following actions

   * Build the SDE for the latest available version if necessary

   * Add the Git repository to the Nix store
   
   * Create or update the Nix profile
   `/nix/var/nix/profiles/per-user/$USER/bf-sde`

   * Add the SDE package and Git repository (from the Nix store) to
   the profile

The Git working copy is no longer needed after this.  The installation
can be performed by any user, including `root`.  The only difference
is the location of the Nix profile (via the `USER` environment
variable).  The packages can be used by any user in any case.  For a
system-wide deployment, it would make sense to perform the
installation as `root` and add
`/nix/var/nix/profiles/per-user/root/bf-sde/bin` to `PATH` in the
system-wide shell profile to make it available for all users.

After the installation, the profile contains a command that launches
the shell for the latest version of the SDE, for example

```
/nix/var/nix/profiles/per-user/$USER/bf-sde/bin/sde-env-9.2.0 
```

Executing this command has exactly the same effect as `make env` or
`make env VERSION=v9_2_0` discussed in the previous section

```
$ /nix/var/nix/profiles/per-user/$USER/bf-sde/bin/sde-env-9.2.0 
Using Nix expression from /nix/var/nix/profiles/per-user/gall/bf-sde
nix-shell  -I nixpkgs=/nix/var/nix/profiles/per-user/gall/bf-sde/ -E "with import <nixpkgs> {}; bf-sde.v9_2_0.mkShell"  || true

Barefoot SDE 9.2.0

Load/unload kernel modules: $ sudo bf_{kdrv,kpkt,knet}_mod_{load,unload}

Compile: $ p4_build.sh <p4name>.p4
Run:     $ run_switchd -p <p4name>
Run Tofino model:
         $ sudo veth_setup.sh
         $ run_tofino_model -p <p4name>
         $ run_switchd -p <p4name> -- --model

Build artefacts and logs are stored in /home/gall/.bf-sde/9.2.0

Use "exit" or CTRL-D to exit this shell.


[nix-shell(SDE-9.2.0):~/bf-sde-nixpkgs]$ 
```

It is also possible to install a specific version, e.g.

```
$ make install-sde VERSION=v9_1_1
```

or all available versions

```
$ make install-sde VERSION=all
```

The latter results in the presence of multiple commands in the
profile, one per version of the SDE

```
$ ls /nix/var/nix/profiles/per-user/gall/bf-sde/bin/
sde-env-9.1.1  sde-env-9.2.0
```

As with any Nix profile, the `nix-env` command can be used to switch
to different versions of the profile at any time, e.g.

```
$ nix-env -p /nix/var/nix/profiles/per-user/$USER/bf-sde --rollback
```

would change to the preceeding generation or

```
$ nix-env -p /nix/var/nix/profiles/per-user/$USER/bf-sde --switch-generation 1
```

would change to the first generation.

### Using additional Dependencies for Developping Control-Plane Programs

By default, the shell contains everything needed to compile and run
any P4 program (essentially via the `p4_build.sh` and `run_switchd.sh`
commands).  It is also desireable to be able to test and run the
control-plane programs associated with the P4 program.  The SDE
environment supports this for Python-based programs that make use of
the gRPC Python-bindings provided by the SDE package.

The default shell already has the environment variable `PYTHONPATH`
set up such that a Python program can access those modules with

```
import bfrt_grpc
```

Apart from that, the Python environment only contains the standard
modules by default.  Suppose our control-plane program requires the
`jsonschema` module.  This will fail with the standard shell

```
$ make env
nix-shell  -I nixpkgs=/home/gall/bf-sde-nixpkgs/ -E "with import <nixpkgs> {}; bf-sde.latest.mkShell" 

Barefoot SDE 9.2.0
[...]

[nix-shell(SDE-9.2.0):~/bf-sde-nixpkgs]$ python2
Python 2.7.17 (default, Oct 19 2019, 18:58:51) 
[GCC 7.4.0] on linux2
Type "help", "copyright", "credits" or "license" for more information.
>>> import jsonschema
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
ImportError: No module named jsonschema
>>> 
```

To solve this problem, the mechanism that invokes `nix-shell` takes an
additional argument, which must be a valid Nix expression which must
evaluate to a function taking the set of available packages as
argument and returning a list of packages to be added to the shell's
environment.  The default value for this expression is

```
pkgs: []
```

which ignores the argument and returns an empty list.  In our example,
we can use the function

```
pkgs:
  with pkgs.python2.pkgs; [ jsonschema ]
```

instead, which returns a list with a single element that contains the
Nix package for the `jsonschema` Python module.  To use it with
`make`, we must set the variable `INPUT_FN` like this:

```
$ make env INPUT_FN="pkgs: with pkgs.python2.pkgs; [ jsonschema ]"
nix-shell  -I nixpkgs=/home/gall/bf-sde-nixpkgs/ -E "with import <nixpkgs> {}; bf-sde.latest.mkShell" --arg inputFn "pkgs: with pkgs.python2.pkgs; [ jsonschema ]"

Barefoot SDE 9.2.0
[...]

[nix-shell(SDE-9.2.0):~/bf-sde-nixpkgs]$ python2
Python 2.7.17 (default, Oct 19 2019, 18:58:51) 
[GCC 7.4.0] on linux2
Type "help", "copyright", "credits" or "license" for more information.
>>> import jsonschema
>>> jsonschema
<module 'jsonschema' from '/nix/store/wlgihkbky9ixwh96awphlgw17a72j1n6-python2.7-jsonschema-2.6.0/lib/python2.7/site-packages/jsonschema/__init__.pyc'>
>>> 
```

If the shell is invoked via the profile, the function must be provided
as a parameter to the command, e.g.

```
$ /nix/var/nix/profiles/per-user/$USER/bf-sde/bin/sde-env-9.2.0 "pkgs: with pkgs.python2.pkgs; [ jsonschema ]"
```

This technique can be used to make any Nix package available in the SDE shell.

## <a name="part2"></a>Part 2: Creating Packages for P4 Applications

In this mode, the SDE packages are used as build-time dependencies to
create packages for ready-to-run P4 applications.  This requires
adding the Nix expressions of the package specifications as Nix
[overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays).

It is recommended to create a new branch from `master` or `release`
and create a directory of the same name.  To create a new application
`foo`, create a new branch and subdirectory

```
$ git checkout -b foo
$ mkdir foo
```

Change to the new directory and add the file `default.nix` with contents

```
{ overlays ? [], ... } @attrs:

import ../. (attrs // {
  overlays = import ./overlay.nix ++ overlays;
})
```

This pulls in the overlay from the main SDE and combines it with an
overlay for the new project defined in `foo/overlay.nix`.  The
`overlays` parameter to this function can, in turn, be used to further
compose the `foo` overlay with another overlay if desired.  An empty
overlay looks like

```
let
  overlay = self: super:
    {
    };
in [ overlay ]
```

For the remainder of this chapter, we use the `packet-broker` branch
as example.  In this case, the SDE-specific part of the overlay looks
as follows (we leave out all parts that are not directly related to
the SDE)

```
let
  overlay = self: super:
    {
      packetBroker = self.recurseIntoAttrs (import ./packet-broker {
        bf-sde = self.bf-sde.latest;
        inherit (self) callPackage;
      });
    };
in [ overlay ]
```

This reads and evaluates the Nix expression in
`packet-broker/default.nix` (note how we select the latest version of
the SDE to be used with this application)

```
{ bf-sde, callPackage }:

{
  packetBroker = callPackage ./packet-broker.nix { inherit bf-sde; };
  configd = callPackage ./configd.nix { inherit bf-sde; };
}
```

The actual build recipes for the P4 program and control-plane Python
application are contained in separate files.

The P4 program is built from `packet-broker/packet-broker/packet-broker.nix`:
```
{ bf-sde, fetchFromGitHub }:

bf-sde.buildP4Program rec {
  version = "0.1";
  name = "packet-broker-${version}";
  p4Name = "packet_broker";
  src = fetchFromGitHub {
    owner = "alexandergall";
    repo = "packet-broker";
    rev = "d490261";
    sha256 = "0wcab5l7xyxbf25g328zpsnxzfwny8fafaarmpknhjwrdr8nj9d1";
  };
}
```

(Note that the `fetchFromGitHub` dependency is [automatically filled
in by
`callPackage`](https://nixos.org/guides/nix-pills/callpackage-design-pattern.html)

This uses the function `buildP4Program` associated with the `bf-sde`
derivation (which, in this example, is actually `bf-sde.latest` as
shown before).  The definition of this function can be found in
`bf-sde/build-p4-program.nix`. It takes the following parameters

   * `name`: The name of the package to generate (only appears in the
     name of the final path in `/nix/store` and is irrelevant
     otherwise)

   * `version`: The version of the package. It is combined with `name`
     to become part of the name of the store path.

   * `p4Name`: The name of the top-level P4 program file to compile,
     without the `.p4` extension.

   * `execName`: The name under which the program will appear in the
     finished package, defaults to `p4Name`.  This is useful if the
     same source code is used to produce different programs, e.g. by
     selecting features via preprocessor symbols.  Each variant of the
     program can be given a different `execName`, which makes it
     possible to combinde them all in the same Nix profile (which
     would otherwise result in a naming conflict because all programs
     would have the same name, i.e. `p4Name`).

   * `path`: An optional path to the program file relative to the root
     of the source directory.

   * `buildFlags`: A string of options to be passed to the
     `p4_build.sh` build script, for example a list of preprocessor
     symbols `"-Dfoo -Dbar"`.

   * `kernelModule`: The `bf_switchd` program (provided by the SDE
     package) requires a kernel module to be present.  Currently,
     there is a selection of three such modules called `bf_kdrv`,
     `bf_kpkt` and `bf_knet` (their function is not discussed here and
     the reader is referred to the documentation supplied by
     Barefoot/Intel).  The `kernelModule` parameter selects which of
     those modules should be loaded automatically when the compiled P4
     program is run.  The value must be one of the names just
     mentioned or `null`, in which case no kernel module is loaded
     when the program is run.
   
   * `src`: A store path containing the source tree of the P4 program,
     typically the result of a call to `fetchgit` or `fetchFromGitHub`.

The script `p4_build.sh` is part of the SDE and performs the actual
compilation of the P4 program (see `bf-sde/p4_build.sh`). The function
`buildP4Program` essentially performs

```
<path-to-sde>/bin/p4_build.sh ${buildFlags} <source-tree>/${path}/${p4Name}.p4
```

and stores the build artefacts in the resulting package. If `execName`
is used, the builder first creates the symbolic link

```
<source-tree>/${path}/${execName}.p4 -> <source-tree>/${path}/${p4Name}.p4
```

and then runs

```
<path-to-sde>/bin/p4_build.sh ${buildFlags} <source-tree>/${path}/${execName}.p4
```

The package then contains an executable named `execName` (defaulting
to `p4Name`) in its `bin` directory which runs the compiled P4 program
with the `bf_switchd` command provided by the SDE.  This script will
also make sure the required kernel module is loaded first.  In our
example, the resulting script would be

```
/nix/store/<hash>-packet-broker-0.1/bin/packet_broker
```

Executing this command is all it takes to load and run the compiled
program on the Tofino ASIC.

Finally, the build recipe for the control-plane process is in
`packet-broker/packet-broker/configd.nix`

```
{ bf-sde, fetchFromGitHub, python2, makeWrapper }:

python2.pkgs.buildPythonApplication rec {
  pname = "packet-broker-configd";
  version = "0.1";

  src = fetchFromGitHub {
    owner = "alexandergall";
    repo = "packet-broker";
    rev = "d490261";
    sha256 = "0wcab5l7xyxbf25g328zpsnxzfwny8fafaarmpknhjwrdr8nj9d1";
  };
  propagatedBuildInputs = [
    bf-sde
    (python2.withPackages (ps: with ps; [ jsonschema ipaddress ]))
  ];
  buildInputs = [ makeWrapper ];

  preConfigure = ''cd control-plane'';
  postInstall = ''
    wrapProgram "$out/bin/configd.py" --set PYTHONPATH "${bf-sde}/lib/python2.7/site-packages/tofino"
  '';
}
```

This is really just a straight-forward application of the standard
build procedure for Python applications provided by the Nix package
manager (via the function `buildPythonApplication` associated with the
Python interpreter).  The SDE occurs as a build input to the package
to provide the Python gRPC client module to the control-plane program
by setting the `PYTHONPATH` environment variable before launching the
script.

All build- and run-time dependencies required by the program must be
added to the `buildInput` and `propagatedBuildInputs` attributes.
Note that Python modules that are needed at run-time must be added as
the latter variant.  Also note the subtle difference between this code
and the expression

```
with pkgs.python2.pkgs [ jsonschema ]
```

used with `nix-shell`.  This merely sets `PYTHONPATH`, where as the
function `python2.withPackages` creates a run-time Python environment
that contains all specified packages.  The interested reader is
referred to the [Python
section](https://nixos.org/manual/nixpkgs/stable/#python) of the
Nixpkgs manual.

## <a name="part3"></a>Part 3: The Nix package manager

The [Nix package manager](https://nixos.org/manual/nixpkgs/stable/),
a.k.a. _Nixpkgs_, is an alternative to conventional package managers
like `deb` or `rpm`. It differs substantially in the manner in which
packages and their dependencies are described and managed. There even
exists an entire Linux distribution called [NixOS](https://nixos.org/)
which is based on it.

For an introduction to the system, the reader is referred to the links
given above.  In addition, the excellent [Nix
pills](https://nixos.org/guides/nix-pills/index.html) series of
articles provides a more in-depth tour through the inner workings of
the package manager.

The key feature of Nix is the use of a purely functional,
domain-specific programming language (DSL) to describe how each
package is built from source and how it depends on other packages.
This allows for a puerly declarative description of the entire package
collection (an in the case of NixOS the entire operating system).

### Installing Nix

Nix supports Linux and macOS and doesn't require anything from the
native package manager of the
system. [Installation](https://nixos.org/manual/nix/stable/#ch-installing-binary)
is very simple and easy to undo if necessary.  It is recommended to
use the multi-user installation, which allows any user of the system
to build and use Nix packages.  In this mode, the setup procedure
creates a daemon that performs all builds in an isolated `chroot`
sandbox where only the explicitly decalred dependencies are present.
This is the setup that is assumed to be present throughout this
documentation.

### Package collections

In Nix, the entire package collection is contained in a single object
in terms of the Nix expression language, which currently contains over
60'000 packages.  The definitions of the major packages can be found
in a [single
file](https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/all-packages.nix).
The collection is self-contained in the sense that there are no
references to objects outside of the collection for any package.  This
includes all tool-chains all the way down to compilers and a basic
shell used to bootrstrap the entire system.

This construct makes it possible to have a huge coherent set of
packages with precisely defined dependencies and a very high degree of
reproducability.  The latter means that anyone who uses a specific Nix
expression for the entire collection will be able to exactly reproduce
any set of packages contained within.

The fact that Nix is a lazy language makes it possible to work with
the full set of packages while only actually building those that are
in the dependency tree of the desired packages.

The essence of Nix is that the build instructions for a package are
contained in a function expressed in the Nix language. Due to the
functional nature of Nix, these functions only depend on their inputs
and don't have any side-effects (e.g. there is no global state of any
kind). The output of such a function is a precise description of the
build procedure including parameters to the build script and
references to all dependencies (the actual build is a two-step
process).

The system calculates a cryptographic hash over all inputs to the
function and uses it as the primary name of the resulting package.
Thus, whenever an input changes, the hash changes as well and the
result will be a new package.  In Nix, all packages are immutable,
i.e. once built, they never change.

By convention, all packages are stored in `/nix/store` and a typical
entry looks like

```
/nix/store/xhdmds2p5j9a2w55ynm83yq6afc6kryk-util-linux-2.33.1
```

The system really only cares about the hash part
(`xhdmds2p5j9a2w55ynm83yq6afc6kry` in this case).  The rest
(`util-linux-2.33.1`) is essentially a convenience for humans and
doesn't have to be unique.

### Profiles and environments

[Profiles](https://nixos.org/guides/nix-pills/install-on-your-running-system.html#idm140737320785984)
and
[environments](https://nixos.org/guides/nix-pills/enter-environment.html#enter-environment)
(see also [here](https://nixos.org/manual/nix/stable/#sec-profiles))
are other key features of Nix.  Nix stores all packages in separate
directories under `/nix/store`.  In a nutshell, environments allow the
user to collect references to packages of his choice in a single
location for easy access and multiple environments can be collected in
a profile.  A profile also introduces the concept of generations and
rollbacks as explained in the links given above.

### Channels

Nixpkgs uses a release cycle similar to other package collections like
Ubuntu.  Every six months, in March and September, there is a new
release named `<year>.<month>`.  At the time of writing, the current
release is 20.03.  The installation procedure will always chose the
"unstable" version of the next release at that point in time.

Nix uses the concept of a
[channel](https://nixos.org/manual/nix/stable/#sec-channels) to refer
to such a release.  A channel consists of a particular version of the
Nix expression for the package collection and a URL where pre-built
pakages can be found.  The latter is also referred to as _binary
cache_.  Whenever Nix needs a package that is not already in the Nix
store, it first checks whether it can be found in the binary cache.
If so, it will fetch the pre-built package, otherwise it will proceed
to build the package from source.

### <a name="nix-store"></a>The Nix store

Every package built by Nix (or, in Nix parlance, every "derivation")
is stored in `/nix/store`. This directory is managed by the Nix
utilities and must never be modified by hand.  To enforce this, it is
mounted as read-only except for brief moments when the Nix tools need
to modify it (this only applies to the multi-user installation of
Nix).

All package dependencies are tracked in a separate database and the
Nix tools make sure that the Nix store is always in a consistent
state.

Nix never deletes anything from the store by itself.  A user can
attempt to delete an object with

```
$ nix-store --delete /nix/store/...
```

However, it is possible that this fails. The reason is that Nix uses a
garbage collector to keep track of objects that are deemed to be
"live".  An object is considered to be live if it is either marked as
a "garbage collection root" or is a direct or indirect dependency of
such a root.  Live objects cannot be removed from the Nix store.

The two main mechanisms which can cause an object to become a garbage
collection root are profiles and `nix-build`.  Any store path
referenced by a profile (created by `nix-env`) automatically becomes a
root.

Any successful execution of `nix-build` creates one or more symbolic
links to the objects that it has created. These links are located in
the directory where `nix-build` was executed and are called `result`
or `result-<number>`.  All of the objects in `/nix/store` to which
these links point also become garbage collection roots.

All currently known roots can be listed with

```
$ nix-store --gc --print-roots
```

To delete all objects which are not live in a single go, any user can
execute

```
$ nix-collect-garbage
```

## Customising a package collection

As described above, a package collection is represented as a single
expression in the Nix language. Users can modify this default
expression in various ways to customize the package collection to suit
their needs.

### Forking

With this method, one forks the [Nixpkgs Git
repository](https://github.com/NixOS/nixpkgs) and uses that copy
instead of the standard Nix expression with the desired customisation
added directly to the original Nix expression.

However, this is usually not convenient.  For example, we could no
longer make use of channels and would have to perform merges with the
upstream repository if we wanted to keep in sync with it.

### Overlays

Even though it is quite tricky how to make this actually work under
the hood (the gory details involve the concept of a [fixed point
calculation](https://nixos.org/guides/nix-pills/nixpkgs-overriding-packages.html#idm140737319685216)),
the ability to customise the package collection in a very fine-grained
manner is a central property of Nix.  This "override" mechanism allows
the user to re-purpose the build recepies of existing packages with
minimal changes to obtain a replacement of the package or create a new
one with different properties.  Once again, the reader is referred to
a [Nix
pill](https://nixos.org/guides/nix-pills/override-design-pattern.html#override-design-pattern)
for details.

Overrides are used in a larger framework known as
[overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays). Essentially,
an overlay extends the pre-defined package collection in a
well-defined manner. The result is the same as if the modifications
had been added to the original expression (like in the forking method)
but the modifications can be stored anywhere outside that original
expression.  The result of combining the original expression with the
overlay produces the "fixed point" of the package collection, in which
all dependencies are completely resolved.

### Hybrid

Overlays are typically installed in such a manner that they are
applied to the "default Nix expression" of the system.  Usually, this
is the channel called `nixpkgs` (or `nixos` if you are working on a
NixOS distribution, but we don't consider this case here).  However,
this underlying package collection is changing over time as the
channel gets updated or even upgraded to a newer Nix release. In other
words, the customisations from the overlays are also changing.  For
example, a dependency from the default Nix expression for a package
added by an overlay could provide a newer version of the package and,
in the worst case, break the package in the overlay.

In many cases, this is acceptable, but it would not be good enough in
an environment where all packages need to be in an exactly specified
state unless they are changed explicitely.

The SDE, at least when used as a run-time system to execute
pre-compiled P4 programs on a production machine, is an example when
it is highly desirable that the software never changes unless it is
upgraded from one release to another.  There are actually different
methods how to achieve this. This repository choses an approach which
is essentially a hybrid of the fork and overlay mehtods.

This works as follows.  We add the [Nixpkgs Git
repository](https://github.com/NixOS/nixpkgs) to our repository as a
sub-module and select one particular commit as our "default Nix
expression".  In our case, we chose the release branch 19.03

```
[~/bf-sde-nixpkgs]$ cat ./.gitmodules 
[submodule "nixpkgs"]
        path = nixpkgs
        url = https://github.com/NixOS/nixpkgs.git
        branch = nixos-19.03
```

and commit

```
[~/bf-sde-nixpkgs]$ git submodule status
 34c7eb7545d155cc5b6f499b23a7cb1c96ab4d59 nixpkgs (19.03-1562-g34c7eb7545d)
```

The submodule lives in the `nixpkgs` subdirectory

```
[~/bf-sde-nixpkgs]$ ls -l nixpkgs/
total 32
-rw-r--r--  1 gall users 1097 Aug 19 12:25 COPYING
-rw-r--r--  1 gall users  968 Aug 19 12:25 default.nix
drwxr-xr-x  5 gall users 4096 Aug 19 12:25 doc
drwxr-xr-x  4 gall users 4096 Aug 19 12:25 lib
drwxr-xr-x  3 gall users 4096 Aug 19 12:25 maintainers
drwxr-xr-x  7 gall users 4096 Aug 19 12:25 nixos
drwxr-xr-x 17 gall users 4096 Aug 19 12:25 pkgs
-rw-r--r--  1 gall users 2374 Aug 19 12:25 README.md
```

We will keep this version fixed until there is a reason to change it,
e.g. to pick up new dependencies for fututre versions of the SDE.

The actual overlay is stored in the `overlay.nix` file, which is
combined with the Nix expression from the submodule with the following
code found in `default.nix`

```
{ overlays ? [], ... } @attrs:

import ./nixpkgs ( attrs // {
  overlays = import ./overlay.nix ++ overlays;
})
```

The upcoming Nix version 3.0 introduces the concept of
[Flakes](https://nixos.wiki/wiki/Flakes), which provides a similar
functionality as the hybrid approach. A future version of the SDE Nix
package will probably use that new mechanism instead.

## Working with Multiple Nix Expressions

It is important to understand that when the SDE package collection is
used, one effectively has a second independent version of the
`nixpkgs` package collection present on the system (the first one is
the result of the initial installation of Nix).

At this point, it is worth while to understand how Nix actually finds
the build recipe for a particular package.

Whenever a Nix command needs to reference the package collection, it
uses the environment variable `NIX_PATH` to find its "top-level" Nix
expression.  With the standard multi-user setup, the value of
`NIX_PATH` is

```
$ echo $NIX_PATH
nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs:/nix/var/nix/profiles/per-user/root/channels
```

It contains a reference to the profile
`/nix/var/nix/profiles/per-user/root/channels`.  By default, this
profile has a single component called `nixpkgs`, which is
(essentially) a clone of one particular commit of the [nixpkgs
repository](https://github.com/NixOS/nixpkgs).  This whole construct
is known (more or less) as a [Nix
channel](https://nixos.wiki/wiki/Nix_channels).

Now consider the command `nix-build`. The primary argument to it is a
file that contains a Nix epxression to evaluate, for example

```
$ nix-build '<nixpkgs>' -A openssh
```

Here, `<nixpkgs>` is actually a simple Nix expression which is
evaluated as follows. The angle brackets instruct the evaluator to
look for the definition of `nixpkgs` in `NIX_PATH` . In this case, the
result is the file-system path
`/nix/var/nix/profiles/per-user/root/channels/nixpkgs`, which happens
to be a symbolic link to a directory

```
$ ls -lL /nix/var/nix/profiles/per-user/root/channels/nixpkgs
total 44
-r--r--r--  1 root root 1097 Jan  1  1970 COPYING
-r--r--r--  1 root root  968 Jan  1  1970 default.nix
dr-xr-xr-x 10 root root 4096 Jan  1  1970 doc
-r--r--r--  1 root root 1480 Jan  1  1970 flake.nix
dr-xr-xr-x  4 root root 4096 Jan  1  1970 lib
dr-xr-xr-x  3 root root 4096 Jan  1  1970 maintainers
dr-xr-xr-x  7 root root 4096 Jan  1  1970 nixos
dr-xr-xr-x 18 root root 4096 Jan  1  1970 pkgs
-r--r--r--  1 root root 5853 Jan  1  1970 README.md
-r--r--r--  1 root root   19 Jan  1  1970 svn-revision
```

When presented with a path to a directory, the evaluator looks for a
file called `default.nix`. If present, it expects it to contain a
valid Nix expression and evaluates it.  Therefore, the following
invocations are equivalent to the one above

```
$ nix-build /nix/var/nix/profiles/per-user/root/channels/nixpkgs -A openssh
$ nix-build /nix/var/nix/profiles/per-user/root/channels/nixpkgs/default -A openssh
$ nix-build -E 'import <nixpkgs> {}' -A openssh
```

The result of the evaluation is a very large "attribute set" (the Nix
version of a Python dictionary or any key/value store in other
languages) containing the complete list of packages provided by this
particular representation of the `nixpkgs` collection.  The source of
this attribute set is the expression defined in

```
/nix/var/nix/profiles/per-user/root/channels/nixpkgs/pkgs/top-level/all-packages.nix
```

The purpose of the `-A` option is to select a particular attribute
from that set. In this example, we have selected the attribute called
`openssh` and the result of the `nix-build` command is the location in
the Nix store where the finished package is stored, e.g.

```
$ nix-build '<nixpkgs>' -A openssh
/nix/store/0ckm75cip412hrx4k7m3yfiyrpmmjl79-openssh-8.3p1
```

Unfortunatley, the `nix-env` command woks differently. It ignores
`NIX_PATH` and, by default, uses `~/.nix-defexpr` to find the Nix
expression. However, by default this also ends up in the profile
`/nix/var/nix/profiles/per-user/root/channels` such that it operates
on the same Nix expression as found by `nix-build` via `NIX_PATH`.

In our example, we can use `nix-env` to show all packages whose names
contain the string `openssh`

```
$ nix-env -qaP openssh
nixpkgs.openssh                openssh-8.3p1
nixpkgs.openssh_with_kerberos  openssh-8.3p1
```

In this output, `nixpkgs` refers to the channel in which the package
is defined (in our case, we only have a single channel but it is
possible to add other channels containing different package
collections), followed by the name of the attribute by which the
package is identified in the attribute set of the package collection.
These names are unique within a channel and can be selected with the
`-A` option in `nix-build`.  The name on the right is the name of the
package as defined in the actual build recipe for the
package.  In this example, it can be found in the file

```
/nix/var/nix/profiles/per-user/root/channels/nixpkgs/pkgs/tools/networking/openssh/default.nix
```

The name is constructed by combining the values of the attributes `pname` and `version`, in this case

```
version = "8.3p1";
pname = "openssh";
```

Contrary to the attribute name of a package, this name is not unqiue
(as in this exaple).  It is essentially ignored by Nix itself and only
appears in the names of paths in `/nix/store` to help humans to have
an idea what a particular store path contains.

To further illustrate how this works, consider the following error

```
$ nix-build '<nixpkgs>' -A bf-sde
error: attribute 'bf-sde' in selection path 'bf-sde' not found
```

It should be clear that this happens because the standard `nixpkgs`
channel doesn't know anything about our custom `bf-sde` package.
There are several ways to make Nix use our own package collection
instead of the default one.

The first method is to enter the top level directory of the
`bf-sde-nixpkgs` clone and execute

```
$ nix-build -A bf-sde
/nix/store/gvgvnc7jk5hzvq51yr4xvjj480b74p87-bf-sde-9.2.0
/nix/store/y48cpnr7jk136gab1qw9pqh2jvph0ifi-bf-sde-9.1.1
```

Note that we did not specify any file to be read by `nix-build`.  In
this case, `nix-build` looks for the file `default.nix` in the current
directory and evaluates it if present.  In our case, the file exists
and contains the expression

```
{ overlays ? [], ... } @attrs:

import ./nixpkgs ( attrs // {
  overlays = import ./overlay.nix ++ overlays;
})
```

Compare this to one of the equivalent methods to call `nix-build` with
the standard channel discussed above

```
$ nix-build -E 'import <nixpkgs> {}' -A openssh
```

This is really almost exactly the same thing, except that the
`nixpkgs` subdirectory in our repository contains a different version
of (https://github.com/NixOS/nixpkgs) than what's in the default
channel.  Apart from that, the main difference is that we call the
local version of `nixpkgs` with an additional attribute set

```
{
  overlays = import ./overlay.nix;
}
```

as argument.  This uses a mechanism called
[overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays) to
add our customizations to the official Nix package collection.

There are other ways to achieve the same thing.  Suppose the Git clone
is located in `/home/gall/bf-sde-nixpkgs`. Then we can use

```
$ nix-build /home/gall/bf-sde-nixpkgs -A bf-sde
/nix/store/gvgvnc7jk5hzvq51yr4xvjj480b74p87-bf-sde-9.2.0
/nix/store/y48cpnr7jk136gab1qw9pqh2jvph0ifi-bf-sde-9.1.1
```

More interesting is to manipulate `NIX_PATH` instead

```
$ NIX_PATH=nixpkgs=/home/gall/bf-sde-nixpkgs nix-build '<nixpkgs>' -A bf-sde
/nix/store/gvgvnc7jk5hzvq51yr4xvjj480b74p87-bf-sde-9.2.0
/nix/store/y48cpnr7jk136gab1qw9pqh2jvph0ifi-bf-sde-9.1.1
```

Note how we are able to use `<nixpkgs>` to evaluate our customized
version of the package collection.

The drawback here is that we have to reference the path of the Git
clone explicitly.  Here is where the profile
`/nix/var/nix/profiles/per-user/root/bf-sde`, which we can create by
calling `make install-sde` in the top-level directory of the repository
clone:


```
$ NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/$USER/bf-sde nix-build '<nixpkgs>' -A bf-sde
/nix/store/y48cpnr7jk136gab1qw9pqh2jvph0ifi-bf-sde-9.1.1
/nix/store/gvgvnc7jk5hzvq51yr4xvjj480b74p87-bf-sde-9.2.0
```

This is the preferred method, because the path to the profile never
changes and is thus suitable to be hard-coded in scripts.  The idea is
that we can use `nix-env` to update the profile whenever our custom
package collection changes and have the scripts always work on the
current version.

This takes care of `nix-buid`, but what about using `nix-env` to work
on our custom collection instead of the default channel?  Recall that
`nix-env` ignores `NIX_PATH`, so we can't use the same trick here.
However, it recognizes the option `-f` to override `~/.nix-defexpr`:

```
$ nix-env -qaP bf-sde
error: selector 'bf-sde' matches no derivations
$ nix-env -f /nix/var/nix/profiles/per-user/$USER/bf-sde -qaP bf-sde
bf-sde.v9_1_1  bf-sde-9.1.1
bf-sde.v9_2_0  bf-sde-9.2.0
```

So, for example, if we want to make the commands from `bf-sde.v9_2_0`
available in the user's profile:

```
$ type run_switchd.sh
-bash: type: run_switchd.sh: not found
$ $ nix-env -f /nix/var/nix/profiles/per-user/$USER/bf-sde -iP -A bf-sde.v9_2_0
installing 'bf-sde-9.2.0'
building '/nix/store/zwkfp482bqw0vx6yr2i2jj1ba6p3vq56-user-environment.drv'...
$ $ type run_switchd.sh
run_switchd.sh is /home/gall/.nix-profile/bin/run_switchd.sh
$ ls -l /home/gall/.nix-profile/bin/run_switchd.sh
lrwxrwxrwx 1 root root 75 Jan  1  1970 /home/gall/.nix-profile/bin/run_switchd.sh -> /nix/store/gvgvnc7jk5hzvq51yr4xvjj480b74p87-bf-sde-9.2.0/bin/run_switchd.sh
```

## SDE Nix overlay

The overlay is structured as follows.  The overlay itself is defined
in `overlay.nix`

```
let
  overlay = self: super:
    rec {
          ## package definitions
    };
in [ overlay ]
```

Please refer to the
[manual](https://nixos.org/manual/nixpkgs/stable/#chap-overlays) and
[NixOS Wiki article](https://nixos.wiki/wiki/Overlays) for details
about how overlays are defined and how they work.  As a convention, we
include overrides of existing packages in `overlay.nix` directly and
put the Nix expressions for new packages in subdirectories.

In particular, the definition of the SDE packages is delegated to the
file `bf-sde/default.nix` by the expression

```
  bf-sde = self.recurseIntoAttrs (import ./bf-sde { pkgs = self; });
```

in the `overlay.nix` file.  That file contains the declarations for
the supported SDE versions.  There you can also find the SHA256 hashes
of the SDE and BSP archives that were given in the table above.

Finally, the actual build recipe (called a _derivation_ in Nix-speak)
is defined in the file `bf-sde/generic.nix`.

### <a name="kernel_support"></a>Kernel support

Kernel modules are required to support some of the features of the
Tofino ASIC, for example to expose the CPU PCIe port as a Linux
network interface.  The modules have to be built to match the kernel
on the host on which they will be loaded.

In general, compiling a kernel module requires the presence of the
directory `/lib/modules/$(uname -r)/build`, where `uname -r` provides
the release identifier of the running kernel.  The `build` directory
is an artefact of the build procedure of the kernel itself. It
contains everything needed to compile a module that will work with
that specific kernel.

How exactly a kernel is built and how the build directory is
instantiated on a system depends heavily on the native package manager
of a given Linux distribution.  Since one of the purposes of the Nix
packaging of the SDE is to gain independence of the native package
manager of any particular Linux distribution, we need a mechanism that
extends this independence to the compilation of kernel modules.

This is achived by adding an abstraction layer to `bf-sde-nixpkgs`
which takes a set of native packages of a given distribution and
creates a plain build directory from them in which the SDE kernel
modules can be compiled successfully.

The current version of `bf-sde-nixpkgs` supports two distributions

   * OpenNetworkLinux (ONL)
   * Debian

ONL is based on Debian but it uses a different method to package the
kernel than standard Debian. It already supplies the entire build
directory in a single `deb` file.  The script `bf-sde/kernels/onl.nix`
performs the conversion to the format expected by the SDE build
script.

Debian splits the contents of the build directory accross three
separate `deb` files and also adds some non-generic processing, which
have to be converted back to the behaviour of a generic kernel build
directory.  The details can be found in `bf-sde/kernels/debian.nix`.

It is worth noting that the native packages contain (apart from header
files and Makefiles) precompiled binaries.  Those need to be patched
to resolve all runtime dependencies (shared objects) from `/nix/store`
rather than the regular locations on the build host.  The conversion
scripts take care of this as well.

Every kernel which needs to be supported by the SDE must be added to
the list returned by the Nix expression in
`bf-sde/kernels/default.nix`.

Each kernel is described by an attribute set containing the attributes
`release` and `build`.  The former must be the exact output of `uname
-r` as it appears on the system on which the SDE will be deployed.
The latter is a derivation (i.e. a path in `/nix/store`) which
contains the kernel build directory for this particular kernel.  The
method used to produce it depends on the flavor of the Linux
distribution of the target system as explained above.

The result of all of this is that the final package for the SDE
contains a subdirectory in `lib/modules` for each kernel release,
which contains the modules for that kernel. For example:

```
$ ls -l /nix/store/gbhsy1rz1g4r66jj590lyr1a2pk5y2sm-bf-sde-9.3.0/lib/modules/
total 12
dr-xr-xr-x 2 root root 4096 Jan  1  1970 4.14.151-OpenNetworkLinux
dr-xr-xr-x 2 root root 4096 Jan  1  1970 4.19.0-11-amd64
dr-xr-xr-x 2 root root 4096 Jan  1  1970 4.19.81-OpenNetworkLinux
$ ls -l /nix/store/gbhsy1rz1g4r66jj590lyr1a2pk5y2sm-bf-sde-9.3.0/lib/modules/4.19.0-11-amd64/
total 16356
-r--r--r-- 1 root root    34480 Jan  1  1970 bf_kdrv.ko
-r--r--r-- 1 root root    61952 Jan  1  1970 bf_knet.ko
-r--r--r-- 1 root root 16642352 Jan  1  1970 bf_kpkt.ko
```

The `bin` directory of the SDE package also contains commands to load
and unload each of the modules.  The load commands use `uname -r` to
locate the module in `lib/modules` and the load it into the kernel
using `insmod`.

## Deployment models

This section pertains mostly to the deployment of the SDE as a
run-time environment to execute a pre-compiled P4 program on a
production system.

### Source deployment

With this model, the Nix expression is installed on the target system
and all dependencies are either copied from a binary cache or built
from source, exactly as described previously.

### Binary deployment

In a binary deployment of a package, the package itself as well as all
of its run-time dependencies need to be copied to the target system.
In Nix, this set is called the
[closure](https://nixos.org/guides/nix-pills/enter-environment.html#idm140737320683776)
of the package.  Because Nix has a precise notion of dependencies, it
can generate the closure for any package in a reliable manner,
i.e. the package is guaranteed to work properly on any system on which
the closure is installed, irrespective of what else is present in the
Nix store of that system.

Given a store path `<path>`, its closure is generated with the
following command

```
$ nix-store -qR <path>
```

The resulting list of store paths is the complete set of recursive
dependencies of `<path>`.  To produce an archive that contains a copy
of these paths, use the following command

```
$ nix-store --export $(nix-store -qR <path>) >closure
```

To install the closure on another system, copy the file and execute
(as root)

```
# nix-store --import <closure
```

Note: without root privileges, the system will complain that the
archive is not signed and refuses to install it.  It is possible to
create signatures for exported closures but this is not covered here.

All packages in the closure are now available on the target system.

Note that with a binary deployment, the Nix expression that was used
to create the packages does not need to be present on the target
system.

### Binary cache

A variant of the source deployment model uses a _binary cache_ to
speed up the build process.  Before a package is built from source,
the system checks whether the package already exists in a location
specified by a URL.  If the package is found there, it will be copied
to the local Nix store.

This is probably the most useful deployment model in an enterprise
scenario and will be documented here some time in the future.
