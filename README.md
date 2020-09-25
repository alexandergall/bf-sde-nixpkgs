# bf-sde-nixpkgs

Nix packaging of the Barefoot SDE.

The first part of this documentation provides a step-by-step
description of how to build packages.  The second part provides some
basic information about the Nix package manager as well as a more
in-depth description of the SDE package itself.

## How to use this repository

The `master` branch contains the current development code. Stable
releases are contained in the `release` branch and tagged with
`v<version>`.

### Install the Nix package manager in multi-user mode

As a regular user, execute (or download and verify the script if you
don't trust the site)

```
$ bash <(curl -L https://nixos.org/nix/install) --daemon
```

and proceed as instructed.  This does not require any support from the
native package manager of the system and should work on any Linux
distribution.

### Clone into the repository

```
$ git clone --branch <tag> --recursive --shallow-submodules <...>
```

Replace `<tag>` with the desired release tag, e.g. `v1`.  This also
clones the `nixpkgs` Git sub-module.

### Fetch and verify source archives

Download the `bf-sde` and `bf-reference-bsp` archives for the desired
version of the SDE from the Barefoot FASTER website (requires
registration and NDA).  The only versions currently supported are
9.1.1 and 9.2.0.  Please verify that the `sha256` sums are as follows

| File  | sha256 |
| ------|--------|
| bf-sde-9.1.1.tar | `be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11` |
| bf-sde-9.2.0.tar | `94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26` |
| bf-reference-bsp-9.1.1.tar | `aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8` |
| bf-reference-bsp-9.2.0.tar | `d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac` |

### Add archives to the Nix store

Execute (as regular user)

```
$ nix-store --add-fixed sha256 bf-sde-<version>.tar bf-reference-bsp-<version>.tar
```

If this step is omitted, the build will fail with a somewhat cryptic
error similar to the following

```
while setting up the build environment: executing 'none': No such file or directory
builder for '/nix/store/fbycbaqb8l502pdwidjhipmd6b6ym6n1-bf-reference-bsp-9.2.0.tar.drv' failed with exit code 1
cannot build derivation '/nix/store/38s8lsm2f7vg93f7n5x98hwbzmdlxfq8-bf-sde-9.2.0-k4_14_151_ONL_7c3bfd.drv': 1 dependencies couldn't be built
error: build of '/nix/store/38s8lsm2f7vg93f7n5x98hwbzmdlxfq8-bf-sde-9.2.0-k4_14_151_ONL_7c3bfd.drv' failed
```

### Build the SDE package

In the top-level directory of the clone of this repository execute (as
regular user)

```
$ nix-build -A bf-sde.<version>
```

where `<version>` is `v` followed by the version of the SDE with dots
replaced by underscores, i.e. currently either `v9_1_1` or
`v9_2_0`. It can be omitted to build all supported SDE versions:

```
$ nix-build -A bf-sde
```

### Build a P4 package

It is assumed that the source tree of the P4 program that should be
packaged is present on the system in an arbitrary location and that it
contains the main P4 program in the top-level directory.  The program
must have the extension `.p4`.

Add a file named `default.nix` to the top-level source directory with
the content

```
{ name, version, sde_version }:

with import <nixpkgs>;
bf-sde.${sde_version}.buildP4Program rec {
  inherit version;
  name = "${name}-${version}";
  p4Name = "${name}";

  src = ./.;
}
```

Then execute (while you're still in the root directory of the
`bf-sde-nixpkgs` repository)

```
$ nix-build -I nixpkgs=. <path-to-p4-source-tree> --argstr name <p4name> --argstr version <version> --argstr sde_version v<sde-version>
```

`<p4name>` must be the name of the main P4 program file without the
`.p4` extenstion, `<version>` is an arbitrary version number assigned
to the P4 program by you (no dots allowed) and `<sde-version>` is the
identifier discussed in the previous section.

### Build a control-plane Python application that uses `bfrt_grpc`

[Note: this functionality is work in progress]

The SDE provides a Python API for the communication between a
control-plane process and `bf_switchd` via GRPC.  The Python modules
are located in the `install/lib/python2.7/site-packaes/tofino`
directory of the SDE.  If the following procedure is implemented, the
control-plane script can simply use

```
import bfrt_grpc.client
```

to import the module.

Nix provides built-in support for building arbitray Python
applications by creating environments with the modules required by the
application automatically.

We assume that the control-plane code contains a valid `setup.py`
file. Add a file `default.nix` to the top-level directory with the
following contents

```
{ sde_version }:

let
  pkgs = import <nixpkgs>;
  bf-sde = pkgs.bf-sde.${sde_version};
in with pkgs; python2Packages.buildPythonApplication rec {
  pname = "<name>";
  version = "<version>";

  src = ./.;

  propagatedBuildInputs = [
    bf-sde
    (python2.withPackages (ps: with ps; [ <module> ... ]))
  ];
  buildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram "$out/bin/configd.py" --set PYTHONPATH "${bf-sde}/install/lib/python2.7/site-packages/tofino"
  '';
}
```

Replace `<name>` and `<version>` with arbitrary values that apply to
your control-plane.  The resulting package will have
`<name>-<version>` in its name in the Nix store.  For each Python
module that your code uses, add a `<module>` parameter in the
`propagatedBuildInputs` section.  For example, if your code contains

```
import ipaddress
import jsonschema
```

you would declare

```
    (python2.withPackages (ps: with ps; [ ipaddres jsonschema ]))
```

Finally, build the package with (while you're still in the root
directory of the `bf-sde-nixpkgs` repository)

```
$ nix-build -I nixpkgs=. <path-to-control-plane-source-tree> --argstr sde_version v<sde-version>
```

### <a name="kernel_support"></a>Kernel support

Kernel modules are required to support some of the features of the
Tofino ASIC, for example to expose the CPU PCIe port as a Linux
network interface.  The modules have to be built to match the kernel
on the host on which they will be loaded.

For this reason, the SDE Nix package requires as additional input to
the build process (apart from the SDE version) the following
information about the kernel for which it should be built.

   * Kernel version
   * Local version
   * Kernel configuration
   * Distinguisher

The version must be one of the official kernel releases available on
the [kernel CDN site](http://cdn.kernel.org/pub/linux/kernel).  For
example, if the version is specified to be 4.14.151, Nix will download
the file
`http://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.151.tar.xz`.

The local version is the string appended to the version number in the
output of `uname -r`, e.g. for

```
$ uname -r
4.19.81-OpenNetworkLinux
```

the local version is `-OpenNetworkLinux`.  This is also the value of
the `CONFIG_LOCALVERSION` kernel configuration option, e.g.

```
$ zcat /proc/config.gz | grep LOCALVERSION=
CONFIG_LOCALVERSION="-OpenNetworkLinux"
```

The kernel configuration is a file with the complete set of kernel
configuration options.  One way to obtain it is to copy it from
`/proc/config.gz` (as shown above) from a system that already runs the
required kernel.

The triple of `version`, `localVersion` and configuration uniquely
identify a kernel.  However, at the time when a module needs to be
loaded, only `version` and `localVersion` are available through the
kernel release identifier from the `uname -r` command.  To be able to
distinguish between kernels that have the same kernel release name but
were built with different configurations, we add another identifier
when looking up the proper module to load.  This identifier is called
`distinguisher` in the list above.

When the SDE is built, the modules for a particular kernel are stored
in the directory

```
lib/modules/$version$localVersion$distinguisher
```

relative to the root of the SDE package.  The SDE also contains a
shell script in its `bin` directory to load each kernel module:

```
bin/bf_kdrv_mod_load
bin/bf_knet_mod_load
bin/bf_kpkt_mod_load
```

These scripts use the following code to locate the module

```
insmod lib/modules/$(uname -r)${SDE_KERNEL_DISTINGUISHER:-}/bf_...
```

To load a module for a kernel with a non-empty distinguisher, simply
set the environment variable `SDE_KERNEL_DISTINGUISHER` to the
appropriate value when calling the scripts.

The list of kernels supported by the SDE Nix package can be found in
`overlays/bf-sde/kernels/default.nix`. In the current version, the
essential part of that file is a list of sets:

```
[
  {
    version = "4.14.151";
    localVersion = "-OpenNetworkLinux";
    distinguisher = "";
    sha256 = "1bizb1wwni5r4m5i0mrsqbc5qw73lwrfrdadm09vbfz9ir19qlgz";
  }
  {
    version = "4.19.81";
    localVersion = "-OpenNetworkLinux";
    distinguisher = "";
    sha256 = "17g2wiaa7l7mxi72k79drxij2zqk3nsj8wi17bl4nfvb1ypc2gi9";
  }
]
```

The `version`, `localVersion` and `distinguisher` attributes are
exactly those explained above.  The `sha256` attribute is a hash of
the kernel archive.  It can be calculated in advance by using the
`nix-prefetech-url` command, for example

```
$ nix-prefetch-url  http://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.14.151.tar.xz 
[96.5 MiB DL]
path is '/nix/store/3wwkk9a4gl9fnxcp4w2hvmbm5cxpdly1-linux-4.14.151.tar.xz'
1bizb1wwni5r4m5i0mrsqbc5qw73lwrfrdadm09vbfz9ir19qlgz
```

The kernel configuration file for a kernel is expected to be in

```
bf-sde/kernels/<version><localVersion><distinguisher>-kernel-config.gz
```

relative to the root of this repository.

To add a new kernel, add a new set to the list in
`overlays/bf-sde/kernels/default.nix` and install the corresponding
configuration file using this naming convetion.

## Introduction

Note: The SDE for the Tofino series of programmable NPUs is currently
only available under NDA from Intel.  The users of this repositories
are assumed to be authorized to download and use the SDA.

In its current form (version 9.2.0 at the time of writing), the SDE
supports only a very specific set of operating systems.  The main
reason for this restriction is the management of build- and run-time
dependencies.  Packaging of the SDE with Nix removes these
restrictions completely and makes it possible to install any version
of the SDE on any system that supports the Nix package manager itself.

## The Nix package manager

The [Nix package manager](https://nixos.org/manual/nixpkgs/stable/),
a.k.a. Nixpkgs, is an alternative to conventional package managers
like `deb` or `rpm`. It differs substantially in the manner in which
packages and their dependencies are described and managed. There even
exists an entire Linux distribution called [NixOS](https://nixos.org/)
which is based on it.

For an introduction to the system, the reader is referred to the links
given above.  In particular, the excellent [Nix
pills](https://nixos.org/guides/nix-pills/index.html) series of
articles provides a more in-depth tour through the inner workings of
the package manager.

The key feature of Nix is the use of a purely functional
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
expression for the entire collection will be abel to exactly reproduce
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
rollbacks as explained in the links given above.  Its use in the
context of the SDE package will be illustrated later in this document.

### Channels

Nixpkgs uses a release cycle similar to other package collections like
Ubuntu.  Every six months, in March and September, there is a new
release named `<year>.<month>`.  At the time of writing, the current
release is 20.03.  The installation procedure will always chose the
current release at that point in time.

Nix uses the concept of a
[channel](https://nixos.org/manual/nix/stable/#sec-channels) to refer
to such a release.  A channel consists of a particular version of the
Nix expression for the package collection and a URL where pre-built
pakages can be found.  The latter is also referred to as _binary
cache_.  Whenever Nix needs a package that is not already in the Nix
store, it first checks whether it can be found in the binary cache.
If so, it will fetch the pre-built package, otherwise it will proceed
to build the package from source.

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
[overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays).

Essentially, an overlay extends the pre-defined package collection in
a well-defined manner. The result is the same as if the modifications
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

The actual overlay is stored in the `overlays` subdirectory

```
[~/bf-sde-nixpkgs]$ ls -l overlays/
total 20
drwxr-xr-x 3 gall users 4096 Sep 10 08:53 bf-sde
-rw-r--r-- 1 gall users 4539 Sep 10 09:43 overlays.nix
```

The two objects are combined by the following expression

```
import ./nixpkgs {
  overlays = import overlays/overlays.nix;
}
```

which can be found in the `default.nix` file in the root of the
repository.

The upcoming Nix version 3.0 introduces the concept of
[Flakes](https://nixos.wiki/wiki/Flakes), which provides a similar
functionality as the hybrid approach. A future version of the SDE Nix
package will probably use that new mechanism instead.

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

### Using profiles with binary deployments

Binary deployment makes it easy and reliable to install any Nix
package on a given system.  However, to access the content of the
package one needs to refer to it by its complete path in the Nix
store.  This is not a problem in itself but consider, for example, the
case when the package provides a program that needs to be run as a
`systemd` service.  One can simply use the store path in the
`ExecStart` option of the service's unit file and everything will
work. However, this method has at least two drawbacks.

First, such a reference will not be recognized by Nix as a root for
the [garbage
collector](https://nixos.org/manual/nix/stable/#sec-garbage-collection).
This means that whenever someone executes `nix-collect-garbage` on the
system, the entire closure will be deleted.

Second, if a new version of the package is installed later, the
reference in the unit file needs to be updated.

Both of these problems can be solved by using a profile dedicated to
the package. Let us assume that we have a single store path `<path>`
and our service is located in `<path>/bin/foo`.  After installing the
closure of `<path>` for the first time, we create a new profile called
`foo` (but the name of the profile is really arbitrary) as root with

```
# nix-env -p /nix/var/nix/profiles/per-user/root/foo -i <path>
```

From now on, we can refer to the package by
`/nix/var/nix/profiles/per-user/root/foo/bin/foo` in the `systemd`
unit file.  Because a profile automatically provides a
garbage-collection root, `<path>` is now protected from being removed
from the Nix store by accident.

Suppose the package is then upgraded and the new package's name is
`<new_path>`.  After installing the closure for `<new_path>`, we can
update the existing profile with

```
# nix-env -p /nix/var/nix/profiles/per-user/root/foo -i -r <new_path>
```

This generates a new generation of the profile `foo` which only
contains whatever is in `<new_path>`. Without the `-r` option, Nix
would try to merge `<new_path>` with `<path>` in the profile, which
would result in a conflict beacuse both paths provide the same file
`bin/foo`.

The path `/nix/var/nix/profiles/per-user/root/foo/bin/foo` now refers
to the new version of the package, i.e. restarting the `systemd`
service would launch the new version of the program.

The `nix-env` command can be used to [switch arbitrarily between the
different generations of the
profile](https://nixos.org/manual/nix/stable/#sec-profiles) or perform
rollbacks (which is just the special case of switching from the
current profile to the one preceeding it).
