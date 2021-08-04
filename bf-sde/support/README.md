# Release Support Functions

The files in `bf-sde/support` provide a library of functions that
facilitate the creation of releases and installers for SDE-based
applications on the platforms supported by the SDE. It also includes a
utility for release management on a device.

These functions assume a specific definition of what exactly a release
is, including a particular versioning scheme as well as a Git work
flow.  The following sections clarify these assumptions. The semantics
of the support functions are [detailed below](#API)

## <a name="prerequisites"/>Prerequisites

### <a name="application"/>Application

In this document, the term _application_ refers to a collection of
packages that implement a particular network function based on a P4
program written for the Tofino-series of networking ASICs that makes
use of the Nix packaging of the Intel Tofino SDE.  Typically, the
application is installed on a device whose sole purpose is to provide
an instance of that network function. In that case we speak of an
_appliance_.

The application is assumed to contain everything needed for a
complete, ready-to use installation. Typically, this includes the
following components

   * A runtime environment to execute the compiled P4 program,
     providing the data-plane of the network function.
   * The control-plane that interacts with the data-plane to configure
     the match-action pipelines to implement the desired behavior of
     the network function. This can be a full-fledged routing daemon
     or a simple script with a static configuration.
   * Definitions for all services that need to be running on the
     system to implement the application, typically a set of
     `systemd` unit files.
   * Other objects that need to be present on the system, e.g. default
     configuration files, directories etc.

### <a name="gitRepoPackaging"/>Git Repository and Nix Packaging

It is clear that the packaging of the compiled P4 program will be
provided by the SDE Nix package.  The support functions further
assumes that the other components of the application are using Nix as
well.  Furthermore, for the purpose of automatic release management,
it is assumed that the complete packaging is provided by a single Git
repository.

### <a name="versioningWorkflow"/>Versioning and Git Workflow

It is assumed that the application uses a single string as a version
identifier.  The support functions treat the version as an opaque
object and do not impose any restrictions other than that it must not
contain a hyphen.  In particular, it is not assumed that there is an
order relation imposed on the version number, though it is probably a
good idea to chose a scheme that has this property.

The following additional assumptions are made:

   * Development of the next release is done on the `master`
     branch. The value of the version identifier on that branch is
     always that of the next release.
   * A release is marked with an annotated Git Tag on the `master`
     branch. The tag must be of the form `release-<version>`.
   * For each release, a separate branch is created at the tagged
     commit whose name is the same as the version identifier.

The workflow for the creation of a new release is as follows, where
`<v>` denotes the current value of the version identifier, denoting
the version of the next release according to the assumptions above.

   * Tag the commit on the `master` branch
     ```
	 git tag -a -m "Release <v>" release-<v>
     ```
   * Create a release branch with version `<v>` as its name
     ```
     git checkout -b <v>
	 ```
   * Back on the `master` branch
      * Bump the version identifier to `<v+1>`
	  * Commit as the start of development of version `<v+1>`

Here, `<v+1>` loosely denotes "a version number following
`<v>`". Again, the generic release manager does not perform any
comparison operation on version identifiers, but the application is
free to chose a scheme that allows this.

The cycle then repeats with `<v+1>` as the version of the next
release.  The tagged releases are also called _principal releases_.

The release manager uses the `git describe` mechanism to create a
unique identifier for every commit relative to its closest release
tag.  The output of `git describe` is of the form
`<tag>-<n>-g<commit>`, where `<tag>` is the name of the closest
annotated tag reachable by the commit, `<n>` is the number of commits
since then and `<commit>` is the abbreviated commit itself.

It is assumed that the only annotated tags that exist in the
repository are the release tags defined above. Hence, the identifiers
are, more specifically, of the form `release-<v>-<n>-g<commit>`.  We
will refer to this as `gitTag` in the remainder of the document. If
`<n>` happens to be zero, the `gitTag` is equal to the tag itself,
i.e. `release-<v>`.

With this definition, every commit belongs to one of two classes:

   1. `gitTag` is of the form `release-<v>`. This marks the principal
      release of version `<v>`.
   2. `gitTag` is of the form `release-<v>-<n>-g<commit>`. This
      identifies the release as an update of the principal release
      `<v>` or a pre-release of the next release.

The second case consists of two sub-cases depending on the value of the
version identifier in the Nix expression.

   * `<v>` is equal to the version. Such a commit is an update of a
     principal release on a release branch.
   * `<v>` is equal to the version of the previous release. Such a
     commit is a pre-release of the upcoming version on the master
     branch.

### <a name="releaseSlices"/>Releases and Slices

A release refers to a collection of packages that represent a
particular version of the application. Apart from the application
itself, a release also includes

   * An ONIE-based installer that brings up a ready-to use appliance
     on a factory-default white box switch.
   * A facility that allows easy installation of new releases on an
     existing system, including support for the coexistence of
     multiple releases on the same device.
   * A mechanism that allows the installation of releases without
     access to the Internet. This is referred to as a _standalone
     installer_ throughout this document.

A complication arises due to various dependencies on the installation
target:

   * The kernel Modules required by `bf_switchd` must match the
     running kernel
   * The runtime environment must contain the BSP that provides
     support for the target platform
   * Some non-SDE-related properties like serial port devices and
     associated configurations for OOB access must be respected

This is independent of the actual application being deployed, hence it
is useful to provide a library that helps the author of an application
to deal with these issues in a generic manner.

Given the list of dependencies above, there are essentially two ways
to organize the ONIE and standalone installers: either one creates a
separate installer for each supported platform/kernel combination, or
one creates a single installer that contains all variants and lets the
installer select the appropriate combination at installation time.

The former is easier to create but the latter is more user-friendly
and this is the model used by the support functions presented here.

The model introduces the notion of a _release slice_, or simply
_slice_. A slice provides a full implementation of the application
specific to a particular kernel and platform.  Consequently, a
_release_ is the union of all slices given by the cross-product of all
kernel modules and platforms.

The lists of kernel modules and platforms supported by an application
must be subsets of the corresponding lists supported by the version
of the SDE on which the application is based.

<a name="sliceFunction"/>
The generic support functions assume that the Nix packaging for an
application provides a function of the form

```
  slice = kernelModules: platform:
    {
	  derivation = ...;
	  ...
	}
```

`kernelModules` must be a derivation that contains the SDE kernel
modules for one particular kernel, i.e. the value of an attribute in
the set returned by `bf-sde/kernels/default.nix` and `platform` must
be the name of a platform supported by the SDE, i.e. one of the
attributes of `bf-sde/bf-platforms/properties.nix`.

The `slice` function must return an attribute set of
derivations. Those derivations will be installed in a Nix profile when
the slice is installed as described in the next section.

The support functions don't make any assumptions about the derivations
returned by the `slice` function with the exception that it must
provide versioning information as follows.  A slice is uniquely
identified by the following elements

   * `version`
   * `gitTag`
   * `kernelID`
   * `kernelRelease`
   * `platform`

The `kernelRelease` is redundant as it is already fixed by the
`kernelID` but it is more useful for the user. The requirement for the
`slice` function is that when it is installed in a profile, it must
contain the following two files in the top-level directory

   * `version`. This file contains the string `<version>:<gitTag>`.
   * `slice`. This file contains the string `<kernelID>:<kernelRelease>:<platform>`

### <a name="profilesServiceActivation"/>Nix Profile and Service Activation

Every application also has a particular _Nix profile_ associated with
it (a path in `/nix/var/nix/profiles`). When a slice is installed, all
of its derivations will be added to a new generation of that profile.
This is what makes the co-existence of multiple versions of an
application and the switching between them possible.

The release manager has two options that deal with service activation.
The option `--activate-current` activates the service from the current
generation of the profile, `--deactivate-current` deactivates it.

What exactly this means depends on the application, which supplies
it's own activation and deactivation methods when building the release
manager.

## <a name="usage"/>Usage

The support functions can be accessed through the `support` attribute
of the SDE Nix package, for example

```
  pkgs = import (fetchTarball {
    url = https://github.com/alexandergall/bf-sde-nixpkgs/archive/...;
    sha256 = ...;
  }) {};
  bf-sde = pkgs.bf-sde.latest;
  support = bf-sde.support;
  release = support.mkRelease { ... };
```

## <a name="API"/>Support Function API

### <a name="mkRelease"/>`mkRelease`

This function creates a release from a set of slices. It takes the
following arguments

   * `slice`. [A function which accepts a kernel module package and a
     platform as arguments](#sliceFunction).
   * `kernelModules`. An attribute set of kernel modules for which to
     create a slice.  This must be a subset of the set produced by
     `bf-sde/kernels/default.nix`
   * `platforms`. A list of platforms for which to create a slice.
     Each element must be a string that matches an attribute in the
     set `bf-sde/bf-platforms/properties.nix`.

The function returns an attribute set of slices obtained by evaluating
`slice` for each member of the cross-product of `kernelModules` and
`platforms`.  The attribute names are composed of the platform and the
kernel ID associated with the kernel module, joined by "_".

### <a name="mkReleaseClosure"/>`mkReleaseClosure`

This function takes the following arguments

   * `release`. A release as returned by the [`mkRelease`
     function](#mkRelease).
   * `name`. An arbitrary string used to form the name of the
     resulting derivation as `"${name}-release-closure"`.

The function returns the result of a call to the `closureInfo`
function provided by `nixpkgs` applied to the set of all derivations
contained in `release`. This is a derivation that contains three files

   * `store-paths`. A list of store paths that make up the closure of
     all input derivations.
   * `registration`. A file suitable for use with `nix-store
     --load-db`.
   * `total-nar-size`. The total size of the NAR file (a Nix-specific
     archive format similar to `tar`) that would contain all store
     paths.

To explain the purpose of this function requires some context related
to the legality of distributing run-time artifacts of the Intel SDE.

Intel allows the distribution of specific parts of the SDE to third
parties for the purpose of running a pre-compiled P4 program. The
`runtimeEnv` function of the SDE package provides an environment that
conforms to this requirement.  However, a problem arises when the Nix
packages are provided by a binary cache.  In a typical setup, the
packages are built by a Nix-specific CI system called _Hydra_. This
system requires the full SDE packages to build the application
packages and thus all packages would end up on the same binary cache,
which would violate the requirements.

One solution to this problem is to maintain a separate binary cache
for the runtime packages.  This can be automated by using a
_post-build hook_ in Hydra, which is essentially a script that is
called whenever a new derivation is built.  That script identifies the
derivations that represent SDE runtime packages and copies them to the
dedicated binary cache.

For packages created with the support functions discussed here, the
objects that need to be copied are releases created by the `mkRelease`
function.  The problem is that a release is not a derivation but a
collection of derivations and the post-build hook will be called
separately for each of them, which makes it difficult to identify
them.  This is where the `releaseClosure` comes in. It is essentially
a container for all derivations that make up a specific release.
Since it is a single derivation, it makes it easy for the post-build
hook to identify it.  In fact, the identification happens through the
name of the derivation, which is the reason for the existence of the
`name` argument to the `releaseClosure` function.

For instance, the call

```
  myclosure = mkReleaseClosure myrelease "myapp"
```

will create a derivation with the the store path

```
/nix/store/<hash>-myapp-release-closure
```

The post-build hook is called with the name of the derivation in the
environment variable `$OUT_PATHS`. The following `bash` fragment could
be used to perform the copy of the closure of the path to a binary
cache

```
DEST=my.binary.cache.example.com
for path in $OUT_PATHS; do
    if [[ $path =~ -release-closure ]]; then
        echo "Copying closure to $DEST"
        nix copy --to ssh://$DEST $path
    fi
done
```

### <a name="mkOnieInstaller"/>`mkOnieInstaller`

This function creates a complete ONIE installer for a release. It is
based on
https://github.com/alexandergall/onie-debian-nix-installer.git and
takes the following arguments

   * `nixProfile`
   * `partialSlice`
   * `platforms`
   * `version`
   * `component`
   * `NOS`
   * `bootstrapProfile`
   * `fileTree`
   * `binaryCache`

The `nixProfile` argument is the name of the Nix profile (usually a
path in `/nix/var/nix/profiles`) where the release will be installed
to.

The `partialSlice` argument must be the same `slice` function that was
used in the call of `mkRelease`, but partially evaluated with the same
kernel module used in the `bootstrapProfile`.

The `profiles` argument must be a list of platform names that the
installer should support.

The remaining arguments are passed to the underlying function from the
Git repository cited above, which is also called
`mkOnieInstaller`. The reader is referred to the
[documentation](https://github.com/alexandergall/onie-debian-nix-installer#readme)
for a description.  Some arguments of that function are not exposed
through this API (e.g. `rootPassword`). However, the derivation
returned by the function is overridable, i.e. it has an `override`
attribute that can be used to override any of the arguments to the
underlying `mkOnieInstaller` function.  For example, to use a
different root password than the default, one would use

```
  onieInstaller = (mkOnieInstaller {
    nixProfile = ...;
	...
  }).override { rootPassword = "foo"; };
```

To support multiple platforms, the installer actually installs all
slices for the requested platforms in temporary profiles. Suppose that
`nixProfile` is `/nix/var/nix/profiles/foo` and `platforms` is `[
"platform-a" "platform-b" ]`.  Then the following profiles will be
installed

   * `/nix/var/nix/profiles/foo-platform-a/foo`
   * `/nix/var/nix/profiles/foo-platform-b/foo`

When the ONIE installer is executed, it will check whether it is being
run on either `platform-a` or `platform-b` (these identifiers need to
be proper ONIE machine names as used in the `onie_machine` variable of
`/etc/machine.conf`). If this is the case, the respective profile is
moved to `/nix/var/nix/profiles/foo` and the other temporary profiles
are deleted.  If the installer runs on an unsupported platform, it
will print a messages and the profile `/nix/var/nix/profiles/foo` will
not be installed. In this case, the temporary profiles will not be
deleted.

The `mkOnieInstaller` function also creates platform-dependent GRUB
configuration files. The main purpose is to support varying settings
of the serial console used for OOB access. The files have the
following contents

```
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="console=<device>,<mode>"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL="console"
```

where `<device>` and `<mode>` are taken from the `serialDevice` and
`serialSetting` attributes of a platform's entry in
`../bf-platforms/properties.nix`.

The files are installed in
`/etc/default/grub-platforms/${platform}`. The default configuration

```
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL="console"
```

is installed as `/etc/default/grub`. At installation time, the
installer checks whether there is a platform-specific file that
matches the install target's platform. If so, it is copied to
`/etc/default/grub`, other wise the default is used.  The directory
`/etc/default/grub-platforms` is removed in any case.

### <a name="mkStandaloneInstaller"/>`mkStandaloneInstaller`

This function creates a standalone installer for a particular release.
The main feature is that it consists of a single file and does not
require network access when executed.

It is a function that takes the following arguments.

   * `release`. The release as created by `mkRelease`.
   * `version`. The version of the release.
   * `gitTag`. A unique identifier of the release as produced by the
     `git-describe` command.
   * `nixProfile`. The Nix profile in which to install the release.
   * `component`. An arbitrary name that identifies the application
     being packaged. It is used by a Hydra post-build hook to copy the
     installer to a location where it can be downloaded.

### <a name="mkReleaseManager"/>`mkReleaseManager`

This function creates a release manager for an application. It takes
the following arguments

   * `version`. The version of the release.
   * `nixProfile`. The Nix profile in which to install the release.
   * `apiType`. The type of API used by the Git repository referenced
     by `repoUrl`. Currently supported are `github` (version 3) and
     `bitbucket` (version 1.0)
   * `repoUrl`. The URL for the Git repository that provides the Nix
     packaging for the application.
   * `apiUrl`. The base URL for the API used for `repoUrl`. For
     `github`, this is usually
     `https://api.github.com/repos/<owner>/<project>`, and for
     `bitbucket` something like
     `https://<site>/rest/api/1.0/projects/<project>/repos/<repo>`
   * `activationCode`. A derivation containing a `bash` fragment that
     defines the functions `activate` and `deactivate` used to
     activate and deactivate the application. It is sourced from the
     main `release-manager` script and has access to the functions
     defined there (e.g. `checkRoot`).
   * `installCmds`. A string containing a `bash` fragment which is
     executed at the end of the installation phase of the
     `release-manager` derivation. It is used to install files and
     directories used by the `activationCode`.

The result is a derivation that contains a command
`bin/release-manager`. It acts on the Nix profile and application
(represented by a Git repository) for which it was built to supply a
simple form of release management.

## <a name="releaseManager"/>Release Manager

The `release-manager` command supports the following options

   * `--list-installed`
   * `--list-available`
   * `--install-release <version> [ --auto-switch ]`
   * `--install-git <git-commit> [ --auto-switch ]`
   * `--update-release <version> [ --auto-switch ]`
   * `--uninstall-generation <gen>`
   * `--activate-current`
   * `--deactivate-current`
   * `--switch-to-generation <gen>`
   * `--cleanup`

The `--install-*` options require network access to various sites (the
Git repository of the application, the generic Nix package cache and
the package repository for pre-built components of the application).
In case generic network access by the device is prohibited by security
policies or technical limitations, releases can also be deployed by
the standalone installer (created by the `mkStandaloneInstaller`),
which does not require any network access at all. All other options of
`release-manager` do not require network access.

#### `--list-installed`

This option lists the currently installed releases

```
$ release-manager --list-installed
Generation Current Release Git Tag                    KernelID       Kernel Release            Platform                   Install date
-----------------------------------------------------------------------------------------------------------------------------------------------------------
         1 *       1       release-1                  Debian11       5.10.0-5-amd64            accton_wedge100bf_32x      2021-04-14 08:00:16.832902563 +0000
```

The generation is a monotonically increasing integer that uniquely
identifies the installed releases.  Every new release installed either
by `release-manager` or a standalone installer is assigned a new
generation number which is equal to the highest generation in the list
plus one.

There can be any number of releases installed at the same time, but
only one of them can provide the service at any given time as detailed
in the description of the `--activate-current` and
`--deactivate-current` options. This release is said to be the
_current_ release and is marked by a `*` in the "Current" column of
the list.

The "Release" and "Git Tag" columns display the versioning
information.

Every instance of the profile corresponds to one particular slice of
the release identified by the Git tag. The "Kernel ID", "Kernel
Release" and "Platform" columns identify the slice.  Note that it is
possible to install multiple slices of the same release to support
upgrades of the kernel and multi-kernel setups.

Finally, the "Install Date" Column gives the time and date at which
the release slice was installed.

**Implementation note**: The notion of generations is taken straight
from the underlying [Nix
profile](https://nixos.org/manual/nix/unstable/package-management/profiles.html).

#### `--list-available`

This option requires access to the Git repository. It uses the
repository's REST API to query the set of exiting tags and looks for
tags of the form `release-<v>`.  For each such tag it prints a line to
inform the user that release version `<v>` is available for
installation.  It will also indicate whether there are any slices of
that release already installed on the system and inform if any updates
are available for the release, for example

```
$ release-manager --list-available
INFO: Checking for release tags of https://github.com//alexandergall/packet-broker-nixpkgs

Version  Status
-----------------------------------------------
       1  Installed, up-to-date version installed in generation 1
```

**Note**: The Github API at `github.com` has a rate-limit of 60
requests per hour per source address. Therefore, it is possible that
the command fails temporarily if the rate-limit has been exceeded.

#### `--install-release <version> [ --auto-switch ]`

This option requires network access to the Git repository, `nixos.org`
and the binary cache that serves pre-built packages for the
release. Given one of the version numbers reported by
`--list-available`, this option downloads the definition of the
release expressed as a Nix expression, fetches the pre-built packages
required by it and installs the slice for the currently running
kernel.

Note that this will install the principal release. If there are any
updates for the release available, they have to be installed
separately with `--update-release`.

This operation is completely safe, reversible and does not affect the
running service.  It only installs the packages and makes them
available for activation with the `--switch-to-generation` option.

If the option `--auto-switch` is specified as well, the command will
also switch to the new generation of the profile automatically.

Due to the nature of Nix, packages are never overwritten or changed in
any way after installation.  This is what makes concurrent versions
without any danger of conflicts possible.

The command will fail if the release is not available. The command
succeeds if the release is already present on the system but it will
print an informational message.

By default, the slice corresponding to the running kernel (as reported
by `uname -r`) and the local platform (as determined from
`/etc/machine.conf`) is installed. To install the slice for a
different kernel, set the `KERNEL_RELEASE` environment variable
accordingly. The kernel must be one of the list of the kernels
supported by the SDE package used in the current release.

#### `--install-git <git-commit> [ --auto-switch ]`

This option requires the same network access as `--install-release`.
While `--install-release` is restricted to installing principal
releases, `--install-git` allows the installation of an arbitrary
commit. It fetches the repository using a Git "remote" called `origin`
and checks out the commit with `git reset --hard`. `<git-commit>` can
be any identifier of a commit (i.e. a "commit-ish" in Git
terminology).  For example, to install the current tip of the branch
`1`, one would use

```
$ release-manager --install-git origin/1
```

If the option `--auto-switch` is specified as well, the command will
also switch to the new generation of the profile automatically.

This is equivalent to using the option `--update-release 1`.

#### `--update-release <version> [ --auto-switch ]`

This option is a shortcut for

```
$ release-manager --install-git origin/<version>
```

to update a release to the most recent commit on the release
branch. This will installed an additional generation with the updates
included. It will not change the existing installation of the
principal release (or that of an update that is not the newest
available).

If the option `--auto-switch` is specified as well, the command will
also switch to the new generation of the profile automatically.

#### `--uninstall-generation <gen>`

This option removes the generation denoted by `<gen>` from the list of
installed releases. It doesn't actually remove any packages unless you
run `--cleanup` as well, but it makes the release unavailable for
activation.

#### `--activate-current`

Mere installation of a release does not instantiate the application
automatically. This only happens after _activation_.  Activation
uses the contents of the current version of the profile to start the
application. What exactly this means depends on the application, but
it typically includes

   * Copying default configurations, e.g. to `/etc`
   * Creating and starting `systemd` services
   * Modifying the default login shell profile to add the application's
     Nix profile to `PATH`

#### `--deactivate-current`

This performs the reverse of `--activate-current`, e.g. stop `systemd`
services.

#### `--switch-to-generation <gen>`

This option is used to switch the service from the currently active
release to another in the list of installed releases.  The argument to
the option must be one of the generations displayed with
`--list-installed`.  The switch is done by first performing a
`--deactivate-current` with the `release-manager` of the current
release (this stops the running instance). Then the current release is
switched to the specified generation. The release is activated by
calling the `release-manager` of the new release with the
`--activate-current` option, which re-starts the service with the new
release.  Note that this also causes the kernel modules of the old
release to be unloaded and re-loaded from the new release.

#### `--cleanup`

The Nix package manager doesn't delete any packages automatically.
Instead, it uses a garbage collector to keep track of packages which
are "in use" (also called _live_).  All packages needed by one of the
installed releases are automatically considered to be live and never
removed.  However, if a release has been uninstalled with
`--uninstall-generation`, it is no longer considered live and subject
to removal.

The `--cleanup` option deletes all packages which are not live. This
can be used to free up disk space if needed.

**Implementation note**: this option essentially calls the
`nix-collect-garbage` utility, which can also be called directly by
the user.
