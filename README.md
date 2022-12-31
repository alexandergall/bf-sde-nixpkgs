# bf-sde-nixpkgs

This project provides packaging of the Intel Tofino SDE for the Nix
package manager.

Disclaimer: The SDE for the Tofino series of P4-programmable ASICs is
currently only available under NDA from Intel.  The users of this
repository are assumed to be authorized to download and use the SDE.

The Nix packaging of the SDE provides two basic functionalities: a
[shell](#sdeShell) in which P4 programs and control-plane programs can
be developed interactively and a system to [create packages for
complete P4-based applications](#packagingP4) ready for deployment.

One of the goals of this work was to make the [shell](#sdeShell) easy
enough to use without requiring any understanding of Nix at all.

To use the system for packaging your own P4 programs clearly requires a
fairly good understanding of the package manager. Explaining how Nix
works in detail is out of scope of this documentation.  Nevertheless,
the text attempts to explain certain key concepts and provides links
to more in-depth documentation on Nix to help the novice user.

This documentation does not explain how to create a complete service
based on a P4 program ready for deployment by an end user, since this
would involve program-specific items and mechanisms outside the scope
of the Nix packages themselves, i.e.  the packages will only make up
one part of such a deployment.

Table of Contents

   * [Motivation](#motivation)
   * [Prerequisites](#prerequisites)
      * [Install the Nix package manager in multi-user mode](#installNix)
      * [Fetch and Verify Source Archives](#fetchAndVerify)
      * [Add archives to the Nix store](#addArchives)
      * [Clone into the Repository](#cloneRepo)
   * [Baseboard and Platform Support](#baseboardPlatform)
   * [P4 Program Development with the SDE Shell](#sdeShell)
      * [Compile](#compile)
      * [Run on ASIC](#runOnASIC)
      * [Run on Tofino Model](#runOnModel)
      * [Run PTF Tests](#runPTF)
      * [Advanced Usage: Adding Packages to the Development Shell](#mkShellAdvanced)
      * [Building a standalone Installer for the SDE](#standaloneSDE)
   * [The SDE Nix Package](#sdePackage)
      * [The Basic SDE Environment](#basicEnv)
      * [SDE Derivations (Sub-Packages)](#subPackages)
      * [SDE Support Functions](#supportFunctions)
      * [P4_16 Example Programs and PTF Tests](#examplesPTF)
      * [Kernel Support](#kernelSupport)
   * [Packaging a P4 Program](#packagingP4)
      * [Writing the Build Recipe as a Nix Expression](#buildRecipeP4)
      * [Building the Package](#buildPackageP4)
      * [What's in the Package](#whatsInPackageP4)
      * [Building for the Tofino Model](#buildForModel)
   * [Packaging a Control-Plane Program for BfRuntime](#packagingCP)
      * [Writing the Build Recipe as a Nix Expression](#buildRecipeCP)
      * [Building the Package](#buildPackageCP)
   * [Using the Packages with a Nix Profile](#usingPackagesWithProfile)
      * [Profile Generations and Garbage Collection](#gc)
   * [Deployment Models](#deploymentModels)
      * [Source Deployment](#sourceDeployment)
      * [Binary Deployment without a Cache](#binaryDeploymentNoCache)
      * [Binary Deployment with a Cache](#binaryDeploymentCache)

## <a name="motivation"></a>Motivation

The first questions the reader will probably ask are "what is Nix" and
"what's the benefit of using it for the SDE"?  The third question will
most likely be "why should I have to read such a long README, clearly
this is way too complicated"?

Those questions are justified and we'll make an attempt to answer them
up front to provide a motivation to read on :)

[Nix](https://nixos.org/manual/nixpkgs/stable/) is a package manager
that uses a functional approach to managing packages and dependencies.
It uses a [specialized functional language](
https://nixos.org/manual/nix/stable/#chap-writing-nix-expressions)
(called the _Nix expression language_) to describe how packages are
built from source and how they relate to each other as build- and
run-time dependencies.  It has the distinctive feature of storing all
packages in separate directories in a dedicated location called the
_Nix store_ (usually `/nix/store`).  The path names of these
directories are of the form

```
/nix/store/<hash>-<name>-<verision>
```

The `<hash>` is a cryptographic hash calculated over all of the inputs
to the package (e.g. packages it depends on, configure an build
options etc.).  This mechanism overcomes most of the limitations of
standard package managers that use the file-system hierarchy standard
(`/bin`, `/lib` etc.) and imprecise dependency specifications prone to
suffer from the dreaded "DLL hell".

The result is that Nix provides a very high degree of reproducibility
for software packages.  This means that, given the specifications of
the packages as a Nix expression, anyone using that specification will
produce the exact same packages. This property is especially useful
for distributing embedded systems which should work reliably and be
robust against accidental changes of run-time dependencies.

Additional features are strict pinning of the exact versions of
dependencies and the peaceful coexistence of arbitrary versions of the
same package. Even though it follows a source-based deployment model
by nature, it has a powerful mechanism called [_binary
cache_](https://cache.nixos.org/) to provide various [deployment
models](#deploymentModels) for pre-built packages.

This leads us to the answer to the question why this is useful for the
Intel/Barefoot SDE.  The SDE is a fairly complex piece of software
with multiple components and a large number of dependencies required
to build. Most of the dependencies must be resolved through the native
package manager of the system on which the SDE is going to be built,
imposing severe restrictions on the choice of build environments. Each
release of the SDE is only certified to support specific versions of
selected Linux distributions.

The Nix packaging of the SDE removes these restrictions by decoupling
the build- and run-time dependencies from the native package manager
of the underlying system.  The advantages of this are obvious:

   * Free choice of build- and run-time systems
   * The work for supporting a new SDE version has to be done only
     once
   * The SDE packages are guaranteed to work on every Linux system on
     which Nix can be installed
   * No interference of dependencies with any other package (including
     different versions of the SDE itself)

The free choice of OS for the run-time system includes platforms with
a Tofino ASIC. The SDE Nix package has been run successfully on
[ONL](http://opennetlinux.org/) (based on Debian 9 and 10), on a plain
[mion](https://docs.mion.io/latest/)-based system as well as stock
Debian distributions.  The only restriction is that the kernel must be
supported by the `bf-drivers` component of the SDE.  The Nix package
provides [a facility to support any kernel on which the modules
provided by `bf-drivers` can be compiled
successfully](#kernelSupport).

The Nix packaging for P4 programs only includes those features of the
SDE which are required at run-time.  This is important because it is
currently legally forbidden to distribute certain components of the
SDE (like the compiler or source code) to third parties which have no
contractual relationship with Intel.

This leaves the final question "why is the documentation so darned
long when this is supposed to be so simple and powerful"?  The answer
is that as with most powerful systems, the learning curve is rather
steep.  This is especially so in this case because Nix differs from
other packaging systems the reader might be familiar with in a profound
manner.  The documentation assumes little to no familiarity with Nix,
which requires a lot of space to explain various methods and concepts.
A README directed at someone with a firm understanding of Nix would
only take a fraction of the space :)


## <a name="prerequisites"></a>Prerequisites

### <a name="installNix"></a>Install the Nix package manager in multi-user mode

As a regular user, execute (or download and verify the script if you
don't trust the site)

```
$ bash <(curl -L https://nixos.org/nix/install) --daemon
```

and proceed as instructed.  This should work on any Linux distribution
because no support of the native package manager is required for the
installation (except for the presence of some basic commands like
`curl` or `rsync`).

### <a name="fetchAndVerify"></a>Fetch and Verify Source Archives

#### SDE

Download the `bf-sde` archive for the desired version of the SDE from
the Intel website (requires registration and NDA). Please verify that
the `sha256` sums are as follows

| File                       | sha256                                                             |
| ------                     | --------                                                           |
| bf-sde-9.1.1.tar           | `be166d6322cb7d4f8eff590f6b0704add8de80e2f2cf16eb318e43b70526be11` |
| bf-sde-9.2.0.tar           | `94cf6acf8a69928aaca4043e9ba2c665cc37d72b904dcadb797d5d520fb0dd26` |
| bf-sde-9.3.0.tgz           | `566994d074ba93908307890761f8d14b4e22fb8759085da3d71c7a2f820fe2ec` |
| bf-sde-9.3.1.tgz           | `71db320fa7d12757127c7da1c16ea98453f4c88ecca7853c73b2bd4dccd1d891` |
| bf-sde-9.3.2.tgz           | `8c637d07b788491b7a81896584be5998feadb7014b3ff42dc37d3cafd5fb56f8` |
| bf-sde-9.4.0.tgz           | `daec162c2a857ae0175e57ab670b59341d39f3ac2ecd5ba99ec36afa15566c4e` |
| bf-sde-9.5.0.tgz           | `61d55a06fa6f80fc1f859a80ab8897eeca43f06831d793d7ec7f6f56e6529ed7` |
| bf-sde-9.5.1.tgz           | `472d10360c30b21ba217eb3bc3dddc4f54182f325c7a5f7ae03e0db3cceba1b0` |
| bf-sde-9.5.2.tgz           | `60f366438c979f0b03d62ab997922e90e2aac447f3937930e3bd1af98c05d48a` |
| bf-sde-9.5.3.tgz           | `fd146282ec80c7fb2aea6f06db9cc871e00ffe3fed5d1de91ce27abdfc8c661a` |
| bf-sde-9.5.4.tgz           | `3971b6b8400920529f0634de6d6211e709ec6e8797f66716d6c8bd31c4f030cb` |
| bf-sde-9.6.0.tgz           | `0e73fd8e7fe22c62cafe7dc4415649f0e66c04607c0056bd08adc1c7710fd193` |
| bf-sde-9.7.0.tgz           | `a4ca94f2d9602535c52613f9d8ad3504b55d99283a4e3dfc64de19e24d767423` |
| bf-sde-9.7.1.tgz           | `dc0eb79b04797a7332f3995f37533a255a9a12afb158c53cdd421d1d4717ee28` |
| bf-sde-9.7.2.tgz           | `e8cf3ef364e33e97f6af6dd4e39331221d61c951ffea30cc7221a624df09e4ed` |
| bf-sde-9.7.3.tgz           | `d45094c47b71fc7a21175436aaa414dd719b21ae0d94b66a5b5ae8450c1d3230` |
| bf-sde-9.7.4.tgz           | `1573577dc2718963dc45210fb9ed75255c68b75a2f219c85a70935dca90f4a16` |
| bf-sde-9.8.0.tgz           | `8d367f0812f17e64cef4acbe2c10130ae4b533bf239e554dc6246c93f826c12a` |
| bf-sde-9.9.0.tgz           | `c4314e76140a9a6f5d644176e0e3b0ca88f0df606b735c2c47c7cf5575d46257` |
| bf-sde-9.9.1.tgz           | `34f23716b38dd19cb34f701583b569b3006c5bbda184490bd70d5e5261e993a3` |
| bf-sde-9.10.0.tgz          | `e0e423b92dd7c046594db8b435c7a5d292d3d1f3242fd4b3a43ad0af2abafdb1` |
| bf-sde-9.11.0.tgz          | `649cd026bc85a23f09c24d010d460d4192ae2a7e009da1f042183ca001d706b3` |
| bf-sde-9.11.1.tgz          | `3880d0ea8e245b0c64c517530c3185da960a032878070d80f4647f3bc15b4a9f` |

#### <a name="BSPArchives"></a> BSP

A BSP (Baseboard Support Package) contains code specific to the
hardware configuration of one or more baseboards, each of which
provides support for one or more platforms.  The SDE uses a
platform-agnostic API to implement functionality that depends on the
baseboard.

The BSP is usually provided by the vendor of the device and has to be
obtained separately.  An exception to this is the reference BSP
implementation provided by Intel, which supports the Tofino1-based
WEDGE series of devices and the Tofino2-based AS9516-32D manufactured
by EdgeCore (which is a subsidiary of Accton).  The baseboard for the
Tofino1 devices is called "accton", the one for the Tofino2 device
"newport".  This BSP is required to build the SDE while all other BSPs
are optional.

The reference BSP is available from Intel, subject to the same NDA as
for the SDE. The BSPs for other platforms must be obtained from the
respective vendors individually. The current release supports the
following BSPs (also see the section on [Baseboard and Platform
Support](#baseboardPlatform))

| Baseboards        | Vendor       | File                                      | Supported SDE version | sha256                                                            |
| -----             | -----        | -----                                     | -----                 | -----                                                             |
| `accton` `model`  | Intel | `bf-reference-bsp-9.1.1.tar` | 9.1.1 | `aebe8ba0ae956afd0452172747858aae20550651e920d3d56961f622c8d78fb8` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.2.0.tar` | 9.2.0 | `d817f609a76b3b5e6805c25c578897f9ba2204e7d694e5f76593694ca74f67ac` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.3.0.tgz` | 9.3.0 | `dd5e51aebd836bd63d0d7c37400e995fb6b1e3650ef08014a164124ba44e6a06` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.3.1.tgz` | 9.3.1 | `b934601c77b08c3281f8dcb235450b80316a42e2683ff29e4c9f2485fffbb51f` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.3.1.tgz` | 9.3.2 | `cb8c126d381ab0dbaf35645d1681c04df5c9675a7ac8231cf10eae5b1a402c9e` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.4.0.tgz` | 9.4.0 | `269eecaf3186d7c9a061f6b66ce3d1c85d8f2022ce3be81ee9e532d136552fa4` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.5.0.tgz` | 9.5.0 | `b6a293c8e2694d7ea8d7b12c24b1d63c08b0eca3783eeb7d54e8ecffb4494c9f` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.5.1.tgz` | 9.5.1 | `34aa5bac92d33afc82cf4106173f7c364e9596c1bbf8d9dab3814f55de330356` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.5.2.tgz` | 9.5.2 | `2d544175f2ad57c9fc6a76305075540ee33253719bb3b9033d8af7dd39409260` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.5.3.tgz` | 9.5.3 | `2990fea8e4c7c1065cdcae88e9291e6dacb1462cc48526e93b80ebb832ac18d2` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.5.4.tgz` | 9.5.4 | `d69264122986a66b0895c4d38bfa84f95f410f8a25649db33e07cd9cb69bdc33` |
| `accton` `model`  | Intel | `bf-reference-bsp-9.6.0.tgz` | 9.6.0 | `88cb4b0978f23c28499faff75098f939374d9071859593353a18c2235e0be461` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.7.0.tgz` | 9.7.0 | `87f91540c0947edff2694cea9beeca78f95062b0aaca812a81c238ff39343e46` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.7.1.tgz` | 9.7.1 | `78aa14c5ec463cd4025b241e898e812c980bcd5e4d039213e397fcb6abb61c66` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.7.2.tgz` | 9.7.2 | `d578438c44a19d2162079d9e4a4a5363a1503a64d7b05e96ceca96dc216f2380` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.7.3.tgz` | 9.7.3 | `33c33ab68dbcf085143e1e8d4a5797d3583fb2044152d063a61764939fa752d4` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.7.4.tgz` | 9.7.3 | `95cb4e81a4284cc22f0e0af9ef85ea1c0396b82bf1f64b79d8396715ddaec408` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.8.0.tgz` | 9.8.0 | `975fa33e37abffa81ff01c1142043907f05726e31efcce0475adec0f1a80f919` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.9.0.tgz` | 9.9.0 | `f73aecac5eef505a56573c6c9c1d32e0fa6ee00218bc08e936fff966f8d2f87a` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.9.1.tgz` | 9.9.1 | `481a2c5e6937f73ff9e9157fb4f313a4d72c0868b3eac94111ee79340c565309` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.10.0.tgz`| 9.10.0| `d222007fa6eee4e3a0441f09ed86b3b6f46df4c7d830b82b08bf6df7f88c4268` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.11.0.tgz`| 9.11.0| `a688b7468db32ea48c5ed83b040743b29f5beec28b3861440ff157cc6a5128ea` |
| `accton` `newport` `model`  | Intel | `bf-reference-bsp-9.11.1.tgz`| 9.11.1| `37aa23ebf4f117bfc45e4ad1fbdb0d366b3bd094dd609f6ef1ec8b37ff6f2246` |
| `aps_bf2556` `aps_bf6064` | APS Networks | `9.5.0_AOT1.5.1_SAL1.3.2.zip` | 9.4.0 | `2e56f51233c0eef1289ee219582ea0ec6d7455c3f78cac900aeb2b8214df0544`|
| `aps_bf2556` `aps_bf6064` | APS Networks | `9.5.0_AOT1.5.4_SAL1.3.4.zip` | 9.5.0 | `510e5e18a91203fe6c4c0aabd807eb69ad53224500f7cb755f7c5b09c8e4525d`|
| `aps_bf2556` `aps_bf6064` | APS Networks | `9.7.0_AOT1.6.1_SAL1.3.5_2.zip` | 9.7.0 9.7.1 9.7.2 9.7.3 | `4941987c4489d592de9b3676c79cb2011a22fe329425e8876fa8ae026fc959ad`|
| `inventec`   | Inventec     | `bf-inventec-bsp93.tgz`                   | 9.3.0 9.3.1 9.4.0 9.5.0 9.6.0 | `fd1e4852d0b7543dd5d2b81ab8e0150644a0f24ca87d59f1369216f1a6e796ad`|
| `inventec`   | Inventec     | `bf-platform_SRC_9.7.0.2.1.tgz`           | 9.7.0 9.7.1 9.7.2 9.7.3 | `8391d5e791ae8b453711a79ed6f6d4372bd9ed6076b3ff54c649b69775b8d9c9`|
| `netberg`    | Netberg      | `bf-platforms-netberg-7xx-bsp-9.7.0-220210.tgz` | 9.7.0 9.7.1 9.7.2 9.7.3 | `ad140a11fd39f7fbd835d6774d9b855f2ba693fd1d2e61b45a94aa30ed08a4f1`|

### <a name="addArchives"></a>Add archives to the Nix store

Execute (as any user)

```
$ nix-store --add-fixed sha256 <bf-sde-archive> <bf-reference-bsp-archive> <bsp-archive> ...
```

Note that the suffixes of the files differ between releases.  The
names in the tables above are exactly as they appear on the download
site.

If this step is omitted, the build will fail with a message like the
following

```
building '/nix/store/jx7is0zvkkpgv59s9hz6izmjn7qwfvh4-SDE-archive-error.drv'...

Missing SDE component bf-sde-9.4.0.tgz
Please add it to the Nix store with

  nix-store --add-fixed sha256 bf-sde-9.4.0.tgz

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
any "garbage collection roots" (in that case the command will fail).

More information on the Nix store can be found [below](#nix-store).

### <a name="cloneRepo"></a>Clone into the Repository

```
$ git clone --branch <tag> https://github.com/alexandergall/bf-sde-nixpkgs.git
$ cd bf-sde-nixpkgs
```

Replace `<tag>` with the desired release tag. See [below](#sdeShell)
how to build and use the SDE for P4 program development.

## <a name="baseboardPlatform"></a> Baseboard and Platform Support

Multiple vendors provide devices based on the Tofino ASIC. The
differences in hardware configuration are isolated by a
platform-independent API in the SDE.  All platform dependent
components are collected in a _Baseboard Support Package_ (BSP).

The BSP is provided by the vendor that builds the device. Support for
these BSPs must be added explicitly to the SDE package.

The SDE package uses the terms _BSP_, _baseboard_ and _platform_ in a
very specific manner to precisely define which components are required
to be installed on a given device:

   * **BSP**. [The software archive provided by a
     vendor](#BSPArchives). Each BSP provides support for one ore more
     baseboards.
   * **baseboard**. A package created from a BSP, providing support
     for one or more platforms.
   * **platform**. A unique identifier for a particular device

The list of BSPs and related baseboards is shown in the [table
above](#BSPArchives). The `model` baseboard is a pseudo-baseboard
which is a variant of the reference BSP that supports the Tofino
software emulation and is not bound to any specific hardware.

This hierarchy provides a unique mapping from platform to baseboard to
BSP (but not the other way round).  Each baseboard can provide support
for multiple platforms.  In this context, a platform denotes one
particular device identified by a unique name. For practical reasons,
the name space used for this is copied from the [Open Network Install
Environment project
(ONIE)](https://github.com/opencomputeproject/onie). The assumption is
that all vendors use ONIE for their devices and thus register a unique
name in that name space.

To be precise, the platform identifier used in the SDE package
corresponds to the `onie_machine` identifier from the
`/etc/machine.conf` file that can be found on the ONIE installer
partition of the device. The same names are used in the
vendor-specific directories of `onie/machine` in the ONIE Git
repository.

The following table shows the list of supported platforms and their
mappings to a specific baseboard (this mapping is provided by
https://github.com/alexandergall/bf-sde-nixpkgs/tree/master/bf-sde/bf-platforms/properties.nix)

<a name="platformIdentifiers"></a>

| Platform                 | Vendor       | Baseboard    |
| -----                    | -----        | -----        |
| `accton_wedge100bf_32x`  | EdegCore     | `accton`     |
| `accton_wedge100bf_32qs` | EdegCore     | `accton`     |
| `accton_wedge100bf_65x`  | EdegCore     | `accton`     |
| `accton_as9516_32d`      | EdegCore     | `newport`     |
| `stordis_bf2556x_1t`     | APS Netwokrs | `aps_bf2556` |
| `stordis_bf6064x_t`      | APS Netwokrs | `aps_bf6064` |
| `inventec_d5264q28b`     | Inventec     | `inventec`   |
| `inventec_d10064   `     | Inventec     | `inventec`   |
| `netberg_aurora_710`     | Netberg      | `netberg`    |
| `model`                  |              | `model`      |
| `modelT2`                |              | `model`      |
| `modelT3`                |              | `model`      |

The `model` platform is a pseudo-platform that exists in order to
support the Tofino ASIC emulator in a consistent manner. The `model`
baseboard uses the same BSP as `reference` configured to provide stubs
for the platform-independent API of the SDE. The `modelT2` and
`modelT3` pseudo-platforms are identical to `model`, but their
intrinsic target type is set to `tofino2` and `tofino3`,
respectively. The purpose of this is that one can call the
`buildP4Program` function for these platforms and have the target
selected automatically, rather than using the `model` platform and
overriding the `target` paramete.

References to platforms and baseboards throughout this document refer
to the table above.

## <a name="sdeShell"></a>P4 Program Development with the SDE Shell

The quickest way to get started with compiling and running your P4
program in an interactive fashion is to use the SDE package in
development mode. This can be done on a system having a Tofino ASIC
installed or any host or VM without such hardware (as long as Nix can
be installed on the platform).  In the latter case, the Tofino ASIC
software emulation (Tofino Model) can be used to test your programs.

The SDE shell is accessed through a command that must be installed
before it can be used.  The installation is performed by building the
`install` target from the `Makefile` in the top-level directory of the
repository. Make sure that you followed all the [prerequisite
steps](#prerequisites) before proceeding. It is sufficient to add only
the `bf-sde` and `bf-reference-bsp` files to the Nix store that
correspond to the SDE version that you want to build.

```
$ make install
installing 'sde-env-9.7.0'
...
```

This installs the command for the latest available version of the SDE
(9.7.0 in this example).  You will find that this build finishes very
quickly and it does not yet build the actual SDE. That will happen
only when the `sde-env-9.7.0` command is executed for the first time.
The reason for this is that only at that time is it known to the
system for which platform and possibly kernel it needs to build. This
process takes place only when the command is run for the first time.

After the build has finished, the user is greeted by the SDE shell

```
$ sde-env-9.7.0
[... lots of build output ...]

Intel Tofino SDE 9.7.0 on platform "accton_wedge100bf_32x"

Load/unload kernel modules: $ sudo $(type -p
bf_{kdrv,kpkt,knet}_mod_{load,unload})

Compile: $ p4_build.sh <p4name>.p4
Run:     $ run_switchd.sh -p <p4name>

Build artifacts and logs are stored in /home/gall/.bf-sde/9.7.0

Use "exit" or CTRL-D to exit this shell.

[nix-shell(SDE-9.7.0):~]$
```

The first line after the output of the build process informs the user
that the hardware platform was identified to be
`accton_wedge100bf_32x`. The command uses the following method to
determine the platform:

   * Use the value passed with the `--platform` option
   * If `--platform` is not supplied, extract the `onie_machine` identifier
     from `/etc/machine.conf`
   * If `etc/machine.conf` does not exist, use the `model` platform as
     a fallback

To select a platform manually, use

```
$ sde-env-<version> --platform=<platform>
```

where `<platform>` can be any of the supported [platform
identifiers](#platformIdentifiers). Note that the existence of
`/etc/machine.conf` depends on the details of the ONIE installation
process.

Within this shell, all commands shown in the introductory text are
available in the search path and all SDE-specific environment
variables are set to make compiling and running P4 programs straight
forward.

The working directory of the SDE shell is inherited from the calling
shell as is the command search path (`PATH`) [unless the `--pure`
option](#pureSDE) is used

The `--command` option can be used to execute arbitrary commands right
after the shell is started. This can be used to automate tasks that
require access to the SDE environment, e.g. to compile a P4
program. For example,

```
$ sde-env-9.7.2 --command "p4c some_program.p4; exit"
```

would attempt to compile `some_program.p4` located in the directory
from which the `sde-env` command is executed and then exit the shell.

To install the command for any other version, pass the version number
(e.g. 9.6.0 or 9.7.0) to the `make` command by setting the `VERSION`
variable, e.g.

```
$ make install VERSION=9.6.0
installing 'sde-env-9.6.0'
...
```

The available versions can be displayed with the `list-versions`
target, e.g.

```
$ make list-versions
9.1.1
9.2.0
9.3.0
9.3.1
9.4.0
9.5.0
9.6.0
9.7.0
```

After installation, the command `sde-env-<version>`
(e.g. `sde-env-9.7.0`) is available in the user's search path using a
Nix-specific feature called a _profile_

```
$ type -p sde-env-9.7.0
/home/gall/.nix-profile/bin/sde-env-9.7.0
```

The commands for different SDE versions can be installed concurrently

```
$ type -p sde-env-9.7.0 sde-env-9.6.0
/home/gall/.nix-profile/bin/sde-env-9.7.0
/home/gall/.nix-profile/bin/sde-env-9.6.0
```

For convenience, a separate `make` target exists to install all
versions

```
$ make install-all
```

The command

```
$ make uninstall
```

removes all `sde-env-*` commands from the search path.

To make a command available to all users, simply perform the
installation as the `root` user to install the command in a global Nix
profile that is part of the search path for all users.

### <a name="compile"></a>Compile

To compile a program, execute `p4_build.sh` with the path to the P4
program to compile, e.g.

```
$ p4_build.sh ./my_example.p4
```

The build artifacts and logfiles are written to
`$HOME/.bf-sde/<sde-version>`.  Please use `p4_build.sh --help` to see
available options.


### <a name="runOnASIC"></a>Run on ASIC

To run the compiled program on the Tofino ASIC, make sure that the SDE
environment has been started with the proper platform support enabled
as described in the [introduction](#sdeShell). To run the P4 program
execute

```
$ run_switchd.sh -p <program_name>
```

where `<program_name>` is the base name of the path provided to the
`p4_build.sh` command without the `.p4` suffix. With the example of
the last section, this would be

```
$ run_switchd.sh -p my_example
```

To get usage information for `run_switchd.sh`, run the command without
any arguments.

The script ends up calling the executable `bf_switchd`, which programs
the ASIC according to the P4 program and provides access to the CLI.
It requires a kernel module for proper operation.  The SDE currently
provides three such modules

   * `bf_kdrv`
   * `bf_kpkt`
   * `bf_knet`

Which of these should be used and what they do is outside the scope of
this text and the reader is referred to the documentation of the SDE
for more information.  The modules `bf_kdrv` and `bf_kpkt` are
mutually exclusive.

Each module has a shell script called `<module>_mod_load`
(e.g. `bf_kdrv_mod_load`) which loads it with the proper parameters.
These scripts must be executed as root. For example using `sudo`

```
$ sudo $(type -p bf_kdrv_mod_load)
```

The modules can be unloaded simply by

```
$ sudo rmmod <module>
```

or by using the commands `<module>_mod_unload` with `sudo` in a
similar fashion as the load commands.

The kernel modules need to be compiled for the exact same kernel which
is running on the current system.  [Kernels must be supported
explicitly](#kernelSupport) by the SDE package.  If the running
kernel is not supported, the `*_mod_load` commands terminate with the
message

```
No modules available for this kernel (<output-of-uname-r>)

```

### <a name="runOnModel"></a>Run on the Tofino Model

Instead of running the program on the actual ASIC, it can also be run
using a register-accurate software emulation called the _Tofino
model_.  This option is available on all systems, including those
having an actual ASIC.

To use the Tofino model, the shell must be started with
`--platform=model`:

```
gall@spare-PB1:~/bf-sde-nixpkgs$ sde-env-9.7.0 --platform=model

Intel Tofino SDE 9.7.0 on platform "model"

Compile: $ p4_build.sh <p4name>.p4
Run:     $ run_switchd.sh -p <p4name>
Run Tofino model:
         $ sudo $(type -p veth_setup.sh)
         $ run_tofino_model.sh -p <p4name>
         $ run_switchd.sh -p <p4name>
         $ sudo $(type -p veth_teardown.sh)
Run Tofino model with custom portinfo file:
         $ sudo $(type -p veth_from_portinfo) <portinfo-file>
         $ run_tofino_model.sh -p <p4name> -f <portinfo-file>
         $ run_switchd.sh -p <p4name>
         $ sudo $(type -p veth_from_portinfo) --teardown <portinfo-file>
Run PTF tests: run the Tofino model, then
         $ run_p4_tests.sh -p  <p4name> -t <path-to-dir-with-test-scripts>

Build artifacts and logs are stored in /home/gall/.bf-sde/9.7.0

Use "exit" or CTRL-D to exit this shell.

[nix-shell(SDE-9.7.0):~]$
```

By default, the model uses `veth` interfaces to connect to the
emulated ports.  These interfaces are set up with the script
`veth_setup.sh`. It requires root privileges and needs to be called
with `sudo`

```
$ sudo $(type -p veth_setup.sh)
```

The `veth` interfaces are persistent. They can be removed at any time
by executing

```
$ sudo $(type -p veth_teardown.sh)
```

To run the Tofino model, execute

```
$ run_tofino_model.sh -p <program_name>
```

The model then waits for a connection from a `bf_switchd`
process, which can be started exactly as for the ASIC:

```
$ run_switchd.sh -p <program_name>
```

Note that the `bf_switchd` process crashes if one of the kernel
modules is loaded when running on the Tofino model (this behaviour is
present at least up to version 9.9.0). In this case, simply unload the
module and restart `run_switchd.sh`.

The default mapping of emulated ports to `veth` interfaces can be
overriden by passing a _portinfo_ file to the model binary. This file
is in JSON and can contain two types of objects:

```
{
  "PortToVeth": [
    {
      "device_port": <dev_port>,
      "veth1": <n1>,
      "veth2": <n2>
    },
    {
      "device_port": <dev_port>,
       "veth1": <n1>,
	   "veth2": <n2>
    },
    ...
  ],
  "PortToIf": [
    {
	  "device_port": <dev_port>,
	  "if": <intf>
	},
    {
	  "device_port": <dev_port>,
	  "if": <intf>
	},
	...
  ]
}
```

The `PortToVeth` object maps a specific device port `<dev_port>` to a
pair of `veth` interfaces with the names `veth<n1>` and `veth<n2>`,
where the device port is connected to `veth<n1>`. The `veth` pair must
exist exist when the model is started.

The `PortToIf` object maps a specific device port `<dev_port>` to the
interface named `intf`. The interface named `intf` must exist when the
model is started.

As a convenience, scripts are provided to create the `veth` pairs
requried by the `PortToVeth` object. The `veth_{setup,teardown}.sh`
scripts create/remove the `veth` pairs required by the default
portinfo file built into the model binary. The default for the Tofino
target maps device ports 0-16 to the `veth` pairs `veth0/veth1`
through `veth31/veth32` and device port 64 to `veth250/veth251` as the
CPU port. For the Tofino2 target, the default is to map device ports
8-24 and port 2 as the CPU port to the same `veth` pairs.

These scripts are part of the standard SDE tooling. The Nix SDE
package provides an additional script `veth_from_portinfo` which takes
a portinfo file as input. When called without any options, the script
generates the `veth` pairs provided by the `PortToVeth` list in the
file (the `PortToIf` object is ignored). When called with the
`--teardown` option, the `veth` pairs are removed:

```
$ cat ports.json
{
    "PortToVeth": [
        {
            "device_port":0,
            "veth1":0,
            "veth2":1
        }
    ]
}
$ sudo $(type -p veth_from_portinfo) ports.json
Creating veth pair 0/1 for device port 0
$ sudo $(type -p veth_from_portinfo) --teardown /tmp/ports.json
Deleting veth pair 0/1
```

The portinfo file must also be supplied to the `run_tofino_model.sh`
script:

```
$ run_tofino_model -p <program> -f <portinfo_file>
```

### <a name="runPTF"></a>Run PTF Tests

The Packet Test Framework (PTF) is also available in the SDE
development shell. The command

```
$ run_p4_tests.sh -p <program_name> -t <test_directory>
```

exercises the tests by executing all python scripts found in the
directory `<test_directory>`. This requires that the P4 program being
tested is run on the Tofino model.

### <a name="mkShellAdvanced"></a>Advanced Usage: Adding Packages to the Development Shell

#### Python modules

The default environment contains the Python interpreter required by
the `bf-drivers` package (Python 3 for SDE 9.7.0 and newer and Python
2 for all older SDE versions), e.g. to access the `bfrt_grcp` modules
provided by that package.  This environment contains only the standard
Python modules as well as all the modules provided by `bf-drivers`.
This interpreter is the preferred match of `python` in the default
search path. All control-plane scripts should be executed with that
interpreter explicitly.

The PTF test scripts run through `run_p4_tests.sh` use a separate
Python environment (but the same interpreter), which is provided by
the `ptf-modules` package.

Any of the control-plane or PTF scripts requiring non-standard Python
modules will fail to run.  To solve this problem, the development
shell can be called with two additional parameters

```
$ sde-env-<version> --python-modules=<module>,... --python-ptf-modules=<module>,...
```

For example, the standard environment doesn't know the `jsonschema`
Python Module

```
$ sde-env-9.7.0
[...]
[nix-shell(SDE-9.7.0):~]$ python -c "import jsonschema; print(jsonschema)"
Traceback (most recent call last):
  File "<string>", line 1, in <module>
ImportError: No module named jsonschema

[nix-shell(SDE-9.7.0):~]$
```

Let's add `jsonschema` to the environment

```
$ sde-env-9.7.0 --python-modules=jsonschema
[...]
[nix-shell(SDE-9.7.0):~]$ python -c "import jsonschema; print(jsonschema)"
<module 'jsonschema' from '/nix/store/6215k8b5pxvshkacq1dlg2m4bx3ij81a-python3-3.8.5-env/lib/python3.8/site-packages/jsonschema/__init__.py'>

[nix-shell(SDE-9.7.0):~]$
```

This works in a similar manner as the native Python virtual
environments (`venv`) but is based on Nix.

Modules added with `--python-ptf-modules` are not visible to the
Python interpteter:

```
$ sde-env-9.7.0 --python-ptf-modules=jsonschema
[...]

[nix-shell(SDE-9.7.0):~]$ python -c "import jsonschema; print(jsonschema)"
Traceback (most recent call last):
  File "<string>", line 1, in <module>
ModuleNotFoundError: No module named 'jsonschema'
```

What happens in this case is that the locations of those modules are
added to the `PTF_PYTHONPATH` environment variable in the shell rather
than adding the modules to the Python interpreter.  The
`run_p4_tests.sh` script merges `PTF_PYTHONPATH` with `PYTHONPATH`
before starting the PTF tests. The result is that modules added with
`--python-ptf-modules` are only visible to the PTF scripts.

The names of the modules must be exactly those used by Nix to identify
them in the package repository. Here is a hack that can be used to get
the list of avaiable modules for the Nixpkgs version used by the SDE:

```
$ echo -e $(nix eval '(with import ./. {}; with builtins; concatStringsSep "\n" (attrNames python3.pkgs))')
```

It needs to be executed in the top-level directory of the
`bf-sde-nixepr` repository. To see the list for a different Python
version, replace `python3` by, e.g. `python2`.

#### <a name="pureSDE"></a>Non-Python Packages and Pure Nix Mode

By default, the shell started by a `sde-env-*` command inherits the
`PATH` from the calling shell. To be precise, `PATH` inside the shell
consists of a number of paths from the Nix store with `PATH` inherited
from the parent shell appended to it. The paths provided by Nix
include `gcc`, `make`, `binutils`, `coreutils` (most standard Unix
utilties), `diff`, `sed`, `gep`, `awk`, `tar`, `gzip`, `bzip`,
`xz`. Those will take precedence over the same commands provided by
the native package manager.

More Nix-based packages can be added to the shell by using the
`--pkgs` option of the `sde-env-*` command. For instance, suppose we
have a system that provides Perl 5.28 with a native package:

```
$ type perl
perl is /usr/bin/perl
$ perl -V:version
version='5.28.1';
```

By default, this version of `perl` would be available in the SDE
shell. To override it with `perl` from Nix, start the shell with

```
$ sde-env-9.7.0 --pkgs=perl
[...]

[nix-shell(SDE-9.7.0):~]$ type perl
perl is /nix/store/5fz4mi6ghnq6qxy8y39m3sbpzwr6nzaw-perl-5.32.0/bin/perl

[nix-shell(SDE-9.7.0):~]$ perl -V:version
version='5.32.0';
```

To remove all dependencies on packages provided by the native package
manager, the SDE shell can be started with the `--pure` option. In
that case, `PATH` is not inherited from the calling shell and all
commands that the user wants to have available in the SDE shell need
to be added explicitly with `--pkgs` (apart from the default packages
mentioned above).

```
$ sde-env-9.7.9 --pure
[...]

[nix-shell(SDE-9.7.0):~]$ type perl
bash: type: perl: not found
```

As with the Python modules, the names passed with the `--pkgs` option
must be the identifiers used by Nix for that specific package. To see
the list of available packages, execute

```
$ echo -e $(nix eval '(let pkgs = import ./. {}; in with builtins; concatStringsSep "\n" (attrNames pkgs))')
```
in the top-level directory of the `bf-sde-nixpkgs` repository.

### <a name="standaloneSDE"></a>Building a standalone Installer for the SDE

The build procedure using `make install` requires Internet access to
download the source code for various components and to access
pre-built Nix packages from a binary cache. If, for any reason, the
host on which the SDE is intended to be used has no or just restricted
Internet access, it is possible to build a "standalone" installer for
the SDE that does not require network access once it has been copied
to the system.

The installer is created with the `standalone` target

```
$ make standalone
```

for the most recent version or

```
$ make standalone VERSION=<version>
```

for any other supported version. This will create a self-extracting
archive called `sde-env-<version>-standalone-installer` in the user's
home directory. To use it, copy the file to the destination and
execute it as root, e.g.

```
$ sudo sde-env-9.7.0-standalone-installer
```

The only requirement for this to work is that `nixpkgs` has been [installed
on the system](#installNix). After the installation, the
`sde-env-<version>` command is available for all users on the system.

## <a name="sdePackage"></a>The SDE Nix Package

The SDE Nix package provides two types of services. The first is an
environment to build and test a P4 program as explained in the
previous chapter.  This environment includes the P4 compiler, Tofino
ASIC emulator, the Packet Test Framework and, optionally, support for
a specific hardware platform.

The second service is a runtime environment for pre-compiled P4
programs.  This environment only contains the build artifact of a P4
program and the components necessary to execute them on the Tofino
ASIC on a particular platform (including the pseudo-platform `model`,
which executes the program on the ASIC software model).  The use case
for this service is the deployment of P4 programs on hardware
appliances.  The binary packages required for this deployment can be
distributed to users who do not have signed an NDA or software
license agreement with Intel.

How these services are instantiated is described later in this
document.  This section describes how they are composed of smaller
components and how they relate to the SDE environment built according
to the official procedure supported by Intel.

### <a name="basicEnv"></a>The Basic SDE Environment

The standard procedure supported by Intel to build the SDE makes use
of a Python-based framework called _P4 Studio_.  It builds and
installs the components contained in the SDE archive as distributed by
Intel into a directory tree pointed to by the `SDE_INSTALL`
environment variable.  The unpacked SDE archive is referenced by the
`SDE` environment variable.  Many of the tools used to compile and run
P4 programs use both of these variables to locate various components
of the SDE.

The object in the SDE Nix package which comes closest to this can be
built by executing

```
$ nix-build -A bf-sde.<version>
```

where `<version>` is the same identifier for a particular version of
the SDE as described in the section about [using the development
shell](#sdeShell), e.g. `v9_3_0` or `v9_4_0` or `latest`, which is an
alias of the most recent version.

The output of the command is a path in the Nix store (`/nix/store`),
which is a directory containing the same objects as a build with P4
Studio, for example

```
$ nix-build -A bf-sde.latest
/nix/store/8wh2yi3v1vajw6g9gjylankmxafp3g3k-bf-sde-9.3.1
$ ls -l /nix/store/8wh2yi3v1vajw6g9gjylankmxafp3g3k-bf-sde-9.3.1
total 24
lrwxrwxrwx 1 root root   80 Jan  1  1970 bf-sde-9.3.1.manifest -> /nix/store/zxhfhfw4dsm8rvbn9pgrk0b84vk7ii2q-bf-tools-9.3.1/bf-sde-9.3.1.manifest
dr-xr-xr-x 2 root root 4096 Jan  1  1970 bin
dr-xr-xr-x 2 root root 4096 Jan  1  1970 include
dr-xr-xr-x 3 root root 4096 Jan  1  1970 lib
lrwxrwxrwx 1 root root   65 Jan  1  1970 pkgsrc -> /nix/store/zxhfhfw4dsm8rvbn9pgrk0b84vk7ii2q-bf-tools-9.3.1/pkgsrc
dr-xr-xr-x 4 root root 4096 Jan  1  1970 share
```

<a name="userEnvironment"></a>
At this point, it is useful to explain a concept called _user
environment_ (or just environment, for short) used by the Nix package
manager. In Nix, every package exists in a separate directory in the
Nix store, i.e. each one has its own collection of the standard Unix
directories `bin`, `lib`, `share`, `man`, `include` etc. The
environment is a mechanism that makes the individual directories of
multiple packages available from a single location.  This is done by
creating a new directory in `/nix/store` containing a single set of
those directories and creating symbolic links in them to the
corresponding objects in the individual packages. It is then possible
to reference, say, the executables of all packages through a single
path, namely the `bin` directory of the environment.

The output of `nix-build -A bf-sde.latest` is exactly such an
environment.  This particular environment combines some of the
packages described in the next section:

   * `bf-syslibs`
   * `bf-drivers`
   * `bf-utils`
   * `bf-platforms.model`
   * `p4c`
   * `tofino-model`
   * `ptf-modules`
   * `ptf-utils`

For example, the user environment contains the `bf_switchd` command
supplied by `bf-drivers` and the `bfshell` command supplied by
`bf-utils`

```
$ ls -l
/nix/store/8wh2yi3v1vajw6g9gjylankmxafp3g3k-bf-sde-9.3.1/bin/bf_switchd
lrwxrwxrwx 1 root root 75 Jan  1  1970 /nix/store/8wh2yi3v1vajw6g9gjylankmxafp3g3k-bf-sde-9.3.1/bin/bf_switchd -> /nix/store/868l44v30k9b6jh83ha95r7jqgis4h4k-bf-drivers-9.3.1/bin/bf_switchd
$ ls -l
/nix/store/8wh2yi3v1vajw6g9gjylankmxafp3g3k-bf-sde-9.3.1/bin/bfshell
lrwxrwxrwx 1 root root 70 Jan  1  1970 /nix/store/8wh2yi3v1vajw6g9gjylankmxafp3g3k-bf-sde-9.3.1/bin/bfshell -> /nix/store/15fmcbjc42pmilzks40h56p8lywl3zpa-bf-utils-9.3.1/bin/bfshell
```

It also contains the following tools used to interact with the SDE

   * `run_switchd.sh`
   * `bfshell`
   * `run_bfshell.sh`
   * `run_tofino_model.sh`
   * `run_p4_test.sh`
   * `p4_build.sh`

It is configured to support the pseudo-platform `model`, i.e. a P4
program started with `run_switchd.sh` would be executed on the Tofino
ASIC emulator.  One way to use the SDE environment on a particular
hardware platform is by using the [SDE Shell](#sdeShell) feature.

In the SDE built in the traditional way by P4 Studio, one needs to set
`SDE` and `SDE_INSTALL` for these tools to work.  In the Nix package,
this is done by shell wrappers around them, i.e. they work without
having to modify the caller's environment.

However, there is a problem when using `p4_build.sh` to compile a P4
program.  In the traditional SDE, the build artifacts are stored in
the SDE itself.  This is not possible with Nix, because all packages
are immutable, i.e. once installed in the Nix store, they can never be
changed.

To solve this problem, the Nix SDE package uses slightly modified
versions of the scripts used to compile P4 programs and run them with
either `run_switchd.sh` or `run_tofino_model.sh` to allow the build
artifacts of P4 programs to be stored outside of `SDE_INSTALL`.  It
uses a new environment variable `P4_INSTALL` instead to specify the
location of P4 compiler artifacts and `SDE_BUILD` for the location of
the build directory.

Apart from this, the Nix package works just like the one built in the
traditional manner.

In principle, one could use the output of `nix-build` directly by
setting `PATH`, `P4_INSTALL` and `SDE_BUILD` appropriately. To avoid
this inconvenience, the Nix package offers a method to easily create a
new shell in which all of these settings are created automatically,
which is exactly what the `sde-env-*` command [described
previously](#sdeShell) does.

<a name="twoStageBuild"></a>
The output of `nix-build` is the closest thing to a binary package of
a traditional package manager. Nix uses a two-stage process when
building packages.  The first stage is called a _derivation_. It is
the direct result of evaluating a Nix expression that contains the
build recipe of a software component. Like everything Nix produces, it
is a file stored in `/nix/store` but with the suffix `.drv` to
distinguish them from actual packages. It is not the package itself
but an encoding of the procedure that needs to be executed to perform
the build (i.e. it the build script to execute, `make` and `configure`
flags etc). The process of generating the `.drv` file is also called
_instantiation_ of the derivation.

The build takes place in a second step when the instructions contained
in the derivation are executed (this is called the _realization_ of a
derivation).  The result of that step is another path in `/nix/store`
(sometimes referred to as the _output path_) which contains the
package itself.

The Nix community usually uses the terms derivation and package
somewhat loosely as synonyms, because the distinction rarely matters in
practice.  We adopt this convention in the rest of this document.

The Nix packaging of the SDE contains many derivations and the command
`nix-build -A bf-sde.<version>` merely creates a particular one as the
default.

The complete set of derivations provided by the SDE Nix package is
provided in the next section.

### <a name="subPackages"></a>SDE Derivations (Sub-Packages)

The SDE itself consists of a set of components which are combined to
create the entities of interest to the user, namely the development
and runtime environments.  There is one package per supported version
of the SDE.  Each version has an attribute (we will see later what
exactly this means) called `pkgs` containing a separate derivation for
each of these components.  They are built automatically when the
default derivation is built (or any other derivation which depends on
them), but they can also be built explicitly if desired (though this
should not be necessary for normal use).  In that case, they can
either be built all at once with

```
$ nix-build -A bf-sde.<version>.pkgs
```

Or individually, e.g.

```
$ nix-build -A bf-sde.<version>.pkgs.bf-drivers
```

In the latter case, all derivations on which the given derivation
depends will be built implicitly.

The following derivations are available

   * `bf-syslibs`
   * `bf-utils`
   * `bf-drivers`
   * `bf-drivers-runtime`
   * `bf-diags`
   * `bf-platforms`
   * `p4c`
   * `tofino-model`
   * `ptf-modules`
   * `ptf-utils`
   * `ptf-utils-runtime`
   * `bf-pktpy` (SDE 9.5.0 and later)
   * `kernel-modules`
   * `kernel-modules-baseboards`

All but the last have a direct correspondence to the components
built by P4 Studio (with the exception of the `ptf-modules` component,
which is split into separate packages for technical reasons).

`kernel-modules` is actually not a derivation but an attribute set of
derivations, each of which provides the modules for one of the
supported kernels.

`kernel-modules-baseboards` is an attribute set that contains one
attribute per supported kernel, like `kernel-modules` but each
attribute is another set with one attribute per supported
baseboard. Each of these attributes is a derivation that contains the
same (baseboard-independent) kernel modules as the corresponding
attribute of `kernel-modules` in addition to modules and arbitrary
files or programs that are specific for a particular baseboard.

`bf-platforms` is also an attribute set of derivations with one
attribute per [supported BSP](#baseboardPlatform).

### <a name="supportFunctions"></a>SDE Support Functions

Due to the fact that Nix packages are implemented as functions, it is
possible to associate additional functionality with them which has the
character of methods in an object-oriented framework (but note that
the Nix expression language is not object-oriented in any sense of the
term).

For instance, each of the SDE packages supported by this repository
(i.e. one for each supported version of the SDE) has a function
associated with it, which, when given the source code of a P4 program,
compiles the program and creates a new package containing a command
that runs `bf_switchd` with the compiled artifacts.  This is more
powerful than using the SDE as a mere build-time dependency as in
traditional package managers, because it includes the build procedure
for the P4 program itself (which could also vary between different SDE
versions).

The following is a list of these additional attributes.  They can all
be accessed with the "attribute path" `bf-sde.<version>.<attribute>`.

   * `version`, type: string
   * `pkgs`, type: attribute set of derivations (see previous section)
   * `buildP4Program`, type: function
   * `modulesForKernel`, type: function
   * `allPlatforms`, type: attribute set
   * `platforms`, type: attribute set
   * `runtimeEnv`, type: function
   * `runtimeEnv'`, type: function
   * `runtimeEnvNoBsp`, type: derivation
   * `baseboardForPlatform`, type: function
   * `support`, type: attribute set of functions
   * `mkShell`, type: function
   * `envCommand`, type: derivation
   * `envStandalone`, type: derivation
   * `test`, type: attribute set of derivations

All of the attributes of type "derivation" can be built with
`nix-build -A <...>`.

For the curious: non-derivation objects can be built by evaluating a
Nix expression as follows (executed from the top-level directory of
the repository)

```
$ nix eval '(with import ./. {}; bf-sde.latest.version)'
"9.5.0"
```

The `mkShell` function is a special object that can only be used by
the `nix-shell` command, for example as used implicitly by the
`sde-env-*` commands built with `make install` that provide a
[development shell](#sdeShell).

`version` is self-explanatory and `pkgs` has been described in the
previous section. The other attributes are explained in detail below.

#### <a name="buildP4Program"></a>`buildP4Program`

This function is at the heart of the mechanism used to build
individual packages for the artifacts of arbitrary P4 programs.  The
definition of this function can be found in
`bf-sde/build-p4/default.nix`. It takes the following arguments

   * `pname`: The name of the package to generate. It doesn't have to
     be unique and appears only in the name of the final path of the
     resulting package in `/nix/store`. Nothing in the Nix machinery
     to build packages depends on this name.

   * `version`: The version of the package. It is combined with `pname`
     to become part of the name of the package in `/nix/store`

   * `p4Name`: The name of the top-level P4 program file to compile,
     without the `.p4` extension and without any directories prepended
     (see `path`)

   * `path`: An optional path to the program file relative to the root
     of the source directory (see `src`)

   * `execName`: optional name under which the program will appear in
     the finished package, defaults to `p4Name`.  This is useful if
     the same source code is used to produce different programs,
     e.g. by selecting features via preprocessor symbols.  Each
     variant of the program can be given a different `execName`, which
     makes it possible to combine them all in the same Nix profile or
     user environment (which would otherwise result in a naming
     conflict because all programs would have the same name,
     i.e. `p4Name`)

   * `target`: optional target for which to compile. Must be one of
     `tofino`, `tofino2` or `tofino3`. The default is the intrinsic
     target for the selected `platform`. Overriding the default only
     makes sense for the `model` pseudo-platform, which supports all
     targets (and defaults to `tofino`). To avoid this override, use
     the pseudo-platforms `modelT2` and `modelT3` instead. Note that
     while the P4 compiler has been supporting `tofino2` for some
     time, the standard build script `p4_build.sh` supports `tofino2`
     and `tofino3` only for SDE 9.7.0 and later.

   * `buildFlags`: optional list of strings of options to be passed to
     the `p4_build.sh` build script, for example a list of
     preprocessor symbols `[ "-Dfoo" "-Dbar" ]`

   * `platform`: optional name of the platform for which to build the
     P4 program. It must be one of the supported [platform
     identifiers](#platformIdentifiers). The default is `model`. The
     effect of this option is to include the `bf-platforms`
     sub-package into the runtime environment that corresponds to the
     baseboard that supports the given platform.

   * `requiredKernelModule`: The `bf_switchd` program (provided by the
     `bf-drivers-runtime` package) requires a kernel module to be
     present (if the P4 program is run on the ASIC rather than the
     Tofino model, which is the assumption here).  Currently, there is
     a selection of three such modules called `bf_kdrv`, `bf_kpkt` and
     `bf_knet` (their function is not discussed here and the reader is
     referred to the documentation supplied by Intel).  This optional
     parameter selects which of those modules is required by the P4
     program.  It is used by the `moduleWrapper` support function
     associated with the package created by `buildP4Program` as
     explained below

   * `src`: A store path containing the source tree of the P4 program,
     typically the result of a call to `fetchgit` or `fetchFromGitHub`

   * `patches`: An optional list of patches to be applied to the
     source tree before building the package

   * `pureArtifacts`: an optional flag whether to remove files from
     the P4 artifacts produced by the compiler that are not needed for
     execution but generate dependencies on the source code of the
     program being compiled as well as the P4 compiler package. This
     option has no effect for SDEs older than 9.7.0. For 9.7.0 and
     later, it removes specific JSON files like `source.json` and
     `frontend-ir.json`. The default is `true`.

The function essentially performs

```
<path-to-sde>/bin/p4_build.sh ${buildFlags} <source-tree>/${path}/${p4Name}.p4
```

where `p4_build.sh` is part of the SDE package.  The build artifacts
are stored in the resulting package. If `execName` is used, the
builder first creates the symbolic link

```
<source-tree>/${path}/${execName}.p4 -> <source-tree>/${path}/${p4Name}.p4
```

and then runs

```
<path-to-sde>/bin/p4_build.sh ${buildFlags} <source-tree>/${path}/${execName}.p4
```

The resulting package contains the following files, where `<name>` is
either `<p4Name>` if no `execName` was given or `execName`

   * `bin/<name>`
   * `share/p4/targets/tofino/<name>.conf`
   * `share/tofinopd/<name>/bf-rt.json`
   * `share/tofinopd/<name>/<name>.conf`
   * `share/tofinopd/<name>/pipe/context.json`
   * `share/tofinopd/<name>/pipe/tofino.bin`

The package will have a derivation produced by the [`runtimeEnv`
support function](#runtimeEnv) as run-time dependency.  That package
contains just enough components of the full SDE to start the
`bf_switchd` process with the artifacts of the compiled program on the
given platform. The `bin/<name>` executable is just a shell script
which invokes `run_switchd.sh`.

If `platform` is one of the model platform (`model`, `modelT2` etc.),
the runtime environment includes the Tofino model binary and the
`run_tofino_model.sh` utility script. The `bin/<name>` executable, in
addition to calling `run_switchd.sh`, also starts
`run_tofino_model.sh` in the background and calls `veth_setup.sh` to
create the `veth` virtual interfaces that connect to the emulated
ports of the model. By default, the output of the `tofino-model` and
`bf_switchd` programs are both sent to `stdout` and `stderr`.  If the
script is called with open file descriptors 3 and/or 4, the model will
write its `stdout` and `stderr` to descriptors 3 and 4, respectively.
For example, calling the script with

```
$ /nix/store/.../bin/<name> >switch.log 2>&1 3>model.log 3>&4
```

will collect all output of `bf_switchd` in `switch.log` and all output
of `tofino-model` in `model.log`.

By default, the model will use a built-in file for mapping ports to
local interfaces.  To use a custom mapping file, assign the absolute
path to the file to the environment variable `TOFINO_MODEL_PORTINFO`
before running the `bin/<name>` script. See the section about [running
the Tofino model](#runOnModel) for details about the portinfo
mechanism.

<a name="p4SupportFunctions"></a>The resulting package has additional
attributes just like the `bf-sde.<version>` packages:

   * `moduleWrapper`, type: function
   * `moduleWrapper'`, type: function
   * `runTest`, type: function

<a name="moduleWrapper"></a> The `moduleWrapper` function creates a
new package which contains the kernel modules for the specified kernel
and a shell wrapper around `bin/<name>` from the package for which the
function is called.  The argument to the function must be the kernel
release identifier produced by executing `uname -r` on a running
instance of the kernel. This wrapper loads the kernel module that has
been specified with `requiredKernelModule` and then calls `bin/<name>`
from the original package. See [modulesForKernel](#modulesForKernel)
for details.

The function `moduleWrapper'` is like `moduleWrapper`, but it takes a
specific kernel module package as argument (i.e. one of the attributes
of the `pkgs.kernel-modules` sub-package).

The `runTest` function runs the PTF tests from test scripts in the
source tree (more documentation on this TBD).

#### <a name="modulesForKernel"></a>`modulesForKernel`

The function takes a kernel release identifier as input and returns a
derivation containing the matching kernel modules.  The release
identifier is a string as returned by the `uname -r` command.  The
function attempts to find a match of the kernel release with the
kernel releases associated with all supported kernels. The logic for
this can be found in `bf-sde/kernels/select-modules.nix`.  There are
three possible results:

   1. There is exactly one match. The function returns the kernel
      module package for the matching kernel (i.e. one of the
      attributes of the `pkgs.kernel-modules` sub-package).
   2. There is no match. The function returns a dummy kernel module
      package that produces an error message when an attempt is made
      to load the module.
   3. There are multiple matches. This means that there are several
      distinct kernels which produce the same release identifier
      (i.e. `uname -r` results in the same string when executed on a
      running instance on each of the kernels).  This is possible
      when, for example, the same kernel is compiled with different
      options.  In this case, the user must disambiguate the choice
      by setting the `SDE_KERNEL_ID` environment variable to the
      desired kernel ID.

#### <a name="allPlatforms"></a>`allPlatforms`

This is an attribute set that contains one attribute for each known
platform as defined in `bf-sde/bf-platforms/properties.nix`.

#### <a name="platforms"></a>`platforms`

The subset of `allPlatforms` that is supported by this SDE.

#### <a name="runtimeEnv"></a>`runtimeEnv`

This function takes a [baseboard identifier](#baseboardPlatform) as
input and returns a derivation just like what is produced with
`nix-build -A bf-sde.<version>` but with a reduced set of packages in
the environment. Instead of the full-fledged SDE, the runtime
environment only provides what's necessary to run a compiled P4
program on the given platform:

   * `bf-syslibs`
   * `bf-drivers-runtime`
   * `bf-utils`
   * `ptf-utils-runtime`
   * `bf-platforms.<baseboard>`

It also contains a reduced set of scripts

   * `run_switchd.sh`
   * `run_bfshell.sh`

(Note that the `ptf-utils-runtime` package is required by
`run_bfshell.sh`). If `baseboard` is `model`, the runtime Environment
also contains the `tofino-model` package (to provide the model binary)
and the script `run_tofino_model.sh`.

In order to deploy a compiled P4 program on a system, it is sufficient
to install the `runtimeEnv` derivation together with the derivation
containing the build artifacts of the program.

#### <a name="runtimeEnvAux"></a>`runtimeEnv'`

This is like `runtimeEnv` but instead of the baseboard identifier, the
function takes a [platform identifier](#baseboardPlatform) as input.
It is a convenience function that uses the
[`baseboardForPlatform`](#baseboardForPlatform) support function and
then calls `runtimeEnv`.

#### <a name="runtimeEnvNoBsp"></a>`runtimeEnvNoBsp'`

This is like `runtimeEnv` but does not install any of the
`bf-platforms` packages in the environment. Hence, it cannot be used
to run P4 programs.  It can be used, for example, to execute one of
the utility scripts like `run_bfshell.sh`.

#### <a name="baseboardForPlatform"></a>`baseboardForPlatform`

This is a function which, given a [platform
identifier](#baseboardPlatform), returns the identifier of the
baseboard that provides support for it.

#### <a name="support"></a>`support`

This is an attribute set of functions that provide support for
creating releases and installers for SDE-based appliances. See
[`bf-sde/support/README.md`](bf-sde/support/README.md) for further
information.

#### <a name="mkShell"></a>`mkShell`

This function is at the heart of the SDE package when used as a
development environment.  When evaluated it creates a new shell in
which the selected SDE is available and can be used to compile and run
P4 programs on-the-fly.  It does not return a proper derivation and
therefore cannot be called with `nix-build`. Instead it must be
evaluated through the `nix-shell` command in a rather cryptic
manner. `mkShell` is used by `envCommand` to provide a user-friendly
way to create a [developmen shell](#sdeShell).

[Standard](#sdeShell) and [advanced](#mkShellAdvanced) usage of this
function through the `sde-env-*` commands has been described earlier.

#### <a name="envCommand"></a>`envCommand`

This derivation contains a single command called `sde-env-<version>`
that launches a [development shell](#sdeShell).

#### <a name="envStandalone"></a>`envStandalone`

This derivation contains a single command called `installer.sh`. It is
a self-extracting archive that contains the `envCommand` derivation
together with all its recursive runtime dependencies (its "closure" in
Nix-speak) for all supported platforms and kernels. The result of
executing the installer is the same as building the `envCommand`
derivation locally but does not require any network access. Its
purpose is to facilitate the installation of the SDE on hosts in
restricted environments.

The installer itself requires a number of Nix packages to be present
on the target system. To avoid a catch-22 situation, the [`standalone`
target](#standaloneSDE) in the top-level `Makefile` of the repository
creates an additional wrapper that installs these dependencies before
calling the installer itself.

#### <a name="examplesPTF"></a>`test`: P4_16 Example Programs and PTF Tests

The SDE comes with a set of example P4 programs. The Nix package
supports the P4<sub>16</sub> example programs to provide a means to
verify the proper working of the SDE and the PTF system.  The example
programs can be exercises as follows.

The `test` attribute is itself a set with one attribute per supported
compiler target (currently `tofino`, `tofino2` and `tofino3` where
`tofino2` is supported for versions 9.7.0 and later and `tofino3` is
supported for versions 9.11.0 and later).  Each target attribute set is
composed of the following attributes

   * `programs`. A set of P4 packages, one for each example program
   * `cases`. A set of derivations, one for each example program. Each
     derivation runs the PTF tests of the example program inside a
     VM. The resulting store path contains three log files
     `model.log`, `switch.log` and `test.log` containing the outputs
     of the `run_tofino_model.sh`, `run_switchd.sh` and
     `run_p4_tests.sh` programs, respectively. It also contains a file
     called `passed` containing a Nix expression with either `true` or
     `false` depending on whether the PTF tests have passed
     successfully or not.
   * `failed-cases`. The subset of `cases` for which the PTF tests
     failed.

The names of the programs are those of the P4 source files located in
the `p4_16_programs` sub directory of the `p4-examples` SDE components.
The list of supported example programs can be displayed by evaluating
a simple Nix expression, for example for the most recent SDE version
and the `tofino` target

```
$ nix eval '(with import ./. {}; builtins.attrNames bf-sde.latest.test.tofino.programs)'
[ "bri_handle" "bri_with_pdfixed_thrift" "tna_action_profile" "tna_action_selector" "tna_alpm" "tna_bridged_md" "tna_checksum" "tna_counter" "tna_custom_hash" "tna_digest" "tna_dkm" "tna_dyn_hashing" "tna_field_slice" "tna_id
letimeout" "tna_lpm_match" "tna_meter_bytecount_adjust" "tna_meter_lpf_wred" "tna_mirror" "tna_multicast" "tna_operations" "tna_pktgen" "tna_port_metadata" "tna_port_metadata_extern" "tna_ports" "tna_proxy_hash" "tna_pvs" "tn
a_random" "tna_range_match" "tna_register" "tna_resubmit" "tna_snapshot" "tna_symmetric_hash" "tna_ternary_match" "tna_timestamp" ]

```

To build all porgrams and run all tests for the latest version and the
`tofino` target in one go, use

```
$ nix-build -A bf-sde.latest.test.tofino
```

To select a single test

```
$ nix-build -A bf-sde.latest.test.tofino.programs.tna_checksum
[ ... ]
/nix/store/hbsfjmyshrmbdwsj9hldqasgrrndr5ka-tna_checksum-0
$ nix-build -A bf-sde.latest.test.cases.tna_checksum
[ ... ]
/nix/store/rg64frv378cw5v6wr6j95457hw544qrk-bf-sde-9.4.0-test-case-tna_checksum
$ cat /nix/store/rg64frv378cw5v6wr6j95457hw544qrk-bf-sde-9.4.0-test-case-tna_checksum/passed
true
```

### <a name="kernelSupport"></a>Kernel Support

Kernel modules are required to support some of the features of the
Tofino ASIC, for example to expose the CPU PCIe port as a Linux
network interface.  The modules have to be built to match the kernel
on the host on which they will be loaded.

In general, compiling a kernel module requires the presence of the
directory `/lib/modules/$(uname -r)/build`, where `uname -r` provides
the release identifier of the running kernel.  The `build` directory
is an artifact of the build procedure of the kernel itself. It
contains everything needed to compile a module that will work with
that specific kernel.

How exactly a kernel is built and how the build directory is
instantiated on a system depends heavily on the native package manager
of a given Linux distribution.  Since one of the purposes of the Nix
packaging of the SDE is to gain independence of the native package
manager of any particular Linux distribution, we need a mechanism that
extends this independence to the compilation of kernel modules.

This is achieved by adding an abstraction layer to `bf-sde-nixpkgs`
which takes a set of native packages (and possibly other inputs which
are not available from the native package manager) of a given
distribution and creates a plain build directory from them in which
the SDE kernel modules can be compiled.

The list of supported kernels is kept in the attribute set defined in
`bf-sde/kernels/default.nix`.  The names of the attributes serve as
identifiers for the kernel.  Each attribute must be a set with the
following attributes

   * `kernelRelease`, **required**

     The release identifier of the kernel as reported by `uname -r`

   * `buildTree`, **required**

     A derivation containing a ready-to use build tree for the modules
     to be compiled in

   * `buildModulesOverrides`, **optional**

     An attribute set used to override the arguments of the derivation
     defined in `bf-sde/kernels/build-modules.nix`

   * `patches`, **optional**

     An attribute set of lists of patches to be applied to the kernel
     module source code.  The name of each attribute must be either a
     SDE version number (e.g. `"9.4.0"`) or `all`. The list of patches
     to apply is obtained by joining the list of `all` with that from
     the attribute that matches the SDE's version.

     The source code is a pristine copy of the source code used to
     build the `bf-drivers` package.  Patches applied by the
     `bf-drivers` derivation are **not** available here.

The package containing the kernel modules for a particular kernel is
built by the function defined in `bf-sde/kernels/build-modules.nix`.
It uses the source of the `bf-drivers` package to build only the
`kdrv` component of it using the kernel build tree from the
`buildTree` attribute.  The resulting package contains scripts to load
and unload each kernel module and the kernel modules themselves in the
directory `lib/modules/${kernelRelease}/`.

The non-trivial part of this procedure is how the `buildTree`
attribute is constructed for each kernel.  The current version of
`bf-sde-nixpkgs` supports three types of systems/distributions:

   * [OpenNetworkLinux (ONL)](http://opennetlinux.org/)
   * Plain Debian
   * [Mion](https://docs.mion.io/latest/)

The Nix expression in `bf-sde/kernels/default.nix` includes utility
functions for each type of system to construct the `buildTree`
attribute.

#### ONL

ONL is based on Debian but it uses a different method to package the
kernel than standard Debian. It already supplies the entire build
directory in a single `deb` file.  The file can be found in the ONL
build directory at the location

```
REPO/<debian-release>/packages/binary-amd64/onl-kernel-<version>-lts-x86-64-all_1.0.0_amd64.deb
```

where `<debian-release>` is the name of the Debian release on which
the ONL image is based (e.g. `stretch` or `buster`) and `<version>` is
the kernel version used in that image (e.g. 4.14 or 4.19).  There is
no online repository where those `.deb` files could be fetched from,
which is why they are included in the `bf-sde-nixpkgs` repository
itself.

#### Plain Debian

Plain Debian splits the contents of the build directory across three
separate `deb` files (`linux-headers`, `linux-headers-common` and
`linux-kbuild`) and also adds some non-generic processing, which have
to be converted back to the behavior of a generic kernel build
directory. The `deb` files are all available from the standard Debian
mirrors.

#### Mion

Mion doesn't create any kind of packages that we could use.  It stores
the kernel build artifacts in the build tree
`build/tmp-glibc/work-shared/<machine>/kernel-build-artifacts`, but it
also requires access to the full kernel sources.  The former must be
present in the `bf-sde-nixpkgs` repository as a tar archive while the
latter is fetched from the Yocto kernel repository.  The git commit
must match exactly the commit for the kernel from the version of
https://github.com/NetworkGradeLinux/meta-mion-bsp.git used to build
the mion image.

## <a name="packagingP4"></a>Packaging a P4 Program

Problem statement: given the source code of a P4 program, compile it
for a specific version of the SDE and create a package that runs it on
a Tofino ASIC on a specific platform or the Tofino model by executing
a single command.

The good news is that all of the real work to accomplish this is
already part of the SDE package. The [`buildP4Program` support
function](#buildP4Program) does exactly what the problem statement
says.

The bad news is that we now have to write our own Nix expression to
call that function :)

At this point, the reader should be at least a little bit familiar
with Nix expressions and derivations.  The `buildP4Program` function
has already been discussed [earlier](#buildP4Program).  In this
chapter, we show how it can be applied to an actual P4 program as an
example.  For this demonstration, we chose the
[`packet-broker`](https://github.com/alexandergall/packet-broker)
program.

The following sections only demonstrate the basic usage of the SDE
package.  To see how a full-fledged deployment can look like, the
reader is referred to the [official packaging of the Packet
Broker](https://github.com/alexandergall/packet-broker-nixpkgs).

### <a name="buildRecipeP4"></a>Writing the Build Recipe as a Nix Expression

The packet broker consists of a P4 program called `packet_broker.p4`,
located in the top-level directory of the Git repository.

To create a package for it, we first create a file `packet-broker.nix`
in the top-level directory of the `bf-sde-nixpkgs` working tree with
the following contents

```nix
{ kernelRelease }:

let
  pkgs = import ./. {};
  packet-broker = pkgs.bf-sde.latest.buildP4Program {
    pname = "packet-broker";
    version = "0.1";
    platform = "accton_wedge100bf_32x";
    src = pkgs.fetchFromGitHub {
      owner = "alexandergall";
      repo = "packet-broker";
      rev = "366999";
      sha256 = "1rfm286mxkws8ra92xy4jwplmqq825xf3fhwary3lgvbb59zayr9";
    };
    p4Name = "packet_broker";
    requiredKernelModule = "bf_kpkt";
  };
in packet-broker.moduleWrapper kernelRelease
```

This is really all it takes.  The rest of this chapter gives a more
detailed explanation of what is going on behind the scenes.

Let's go over the most important elements of this expression. The
first line identifies the expression as a function which takes one
argument called `kernelRelease`.

The `let...in` construct binds expressions to names (i.e. it creates
local variables) and makes them available in the scope of the
following expression.  The value of the variable `pkgs` is the result
of evaluating the Nix expression in the file `default.nix` (the `./.`
path is expanded to `./default.nix` automatically). This is the
standard "boiler plate" found in almost all Nix expressions. It
imports the entire package collection as a single, huge attribute
set. Each attribute in the set represents a package in the collection
(more or less). In particular, the SDE packages for all supported
versions can now be accessed through the attribute `bf-sde` of the
`pkgs` set.

The object `pkgs.bf-sde` is itself an attribute set whose attributes
are the version numbers of all available SDE versions in the form
`v<major>_<minor>_<patch>` and an attribute `latest` which is an alias
for the latest version of the SDE.

We can now understand how the value of the `packet-broker` variable is
created: take the newest version of the SDE (`pkgs.bf-sde.latest`) and
call its function `buildP4Program` with the following attribute set as
argument.  At this point we could have selected any of the supported
SDE versions to build our program with (e.g. `bf-sde.v9_3_1`). The
result is a derivation (which, as a Nix expression, is also an
attribute set), which is assigned to the variable `packet-broker`.
This particular invocation uses a subset of the [arguments expected by
the `buildP4Program` function](#buildP4Program). The most important
input is the `packet-broker` Git repository, which is downloaded at
build-time using the
[`fetchFromGithub`](https://nixos.org/manual/nixpkgs/stable/#chap-pkgs-fetchers)
utility function.

The `platform` argument selects the platform for which to build the
program (`accton_wedge100bf_32x` in this case). This determines which
BSP has to be included in the runtime environment.

The `requiredKernelModule` argument indicates to the function that
this P4 program requires the `bf_kpkt` kernel module to be present
when the program is started.  However, the resulting package does not
contain that module. As explained earlier, this is because the module
must be compiled for the system on which the program will be run
rather than the kernel on which the package is built.

In typical Nix-style, the package created by `buildP4Program` has the
capability to create a new package containing the required kernel
module based on itself.  For that purpose, it has an attribute named
`moduleWrapper`, very much like `buildP4Program` is an attribute of
the SDE package. That attribute is a function and has been described
[earlier](#moduleWrapper). The function takes a kernel release string
as argument.

In this example we assume that the package is built on the same system
on which we want to use it.  Therefore, we can roll these two steps
into one by calling `moduleWrapper` immediately. The `packet-broker`
package becomes a run-time dependency of the final package
automatically.

### <a name="buildPackageP4">Building the Package

To perform the actual build, simply pass our Nix expression to `nix-build`

```
$ nix-build packet-broker.nix
error: cannot auto-call a function that has an argument without a default value ('kernelRelease')
```

Well, that was to be expected. We need to somehow pass the local
kernel release to the function in `test.nix` as an argument.  That is
the purpose of the `--argstr` option of `nix-build` (it treats its
argument as a Nix string without having to quote it, as opposed to
using the `--arg` option):

```
$ nix-build packet-broker.nix --argstr kernelRelease $(uname -r)
[ ... ]
/nix/store/n3mvk07nl25allcjm5vrm7yfnsma5zsz-packet_broker-module-wrapper
```

### <a name="whatsInPackageP4"></a>What's in the Package

The user of the package doesn't have to understand anything described
in this section. This is purely for the enjoyment of the curious
reader.

Let's see what's inside the package we just created

```
$ ls -lR /nix/store/n3mvk07nl25allcjm5vrm7yfnsma5zsz-packet_broker-module-wrapper
/nix/store/n3mvk07nl25allcjm5vrm7yfnsma5zsz-packet_broker-module-wrapper:
total 4
dr-xr-xr-x 2 root root 4096 Jan  1  1970 bin

/nix/store/n3mvk07nl25allcjm5vrm7yfnsma5zsz-packet_broker-module-wrapper/bin:
total 4
-r-xr-xr-x 1 root root 898 Jan  1  1970 packet_broker-module-wrapper
```

It's a single shell script that loads the `bf_kpkt` kernel module if
it's not already loaded and then starts the actual P4 program. Simply
executing this script is enough to launch the P4 program on the Tofino
ASIC. The last line

```
exec /nix/store/2aj27ji70991ij6g3pbvizczfcrazdw3-packet-broker-0.1/bin/packet_broker "$@"
```

references the package `packet-broker`, which occurred as an
intermediary step during the evaluation of `packet-broker.nix`. It has
now become a run-time dependency of the `packet_broker-module-wrapper`
package.  We can see all the immediate run-time dependencies with

```
$ nix-store -q --references /nix/store/n3mvk07nl25allcjm5vrm7yfnsma5zsz-packet_broker-module-wrapper
/nix/store/0kcx6s8gxysnygd8kxa502xfdfm1n28y-gnugrep-3.4
/nix/store/a3fc4zqaiak11jks9zd579mz5v0li8bg-bash-4.4-p23
/nix/store/2aj27ji70991ij6g3pbvizczfcrazdw3-packet-broker-0.1
/nix/store/n599lhxiidv6fpiz43y2mld2nwnscc5s-kmod-27
/nix/store/d8jfwymqiiylcf3dl2pvj8ldx4c1jcnk-bf-sde-9.5.0-kernel-modules-4.19.0-16-amd64
/nix/store/g9qsf6rcy467dxa6gxdh4sw8wm5p6alg-gawk-5.1.0
```

Apart from the utilities required by the shell script and the
`packet-broker` package, we can see an additional package containing
the kernel modules just for the local system (which happens to be a
Debian system in this example)

```
$ ls -l /nix/store/d8jfwymqiiylcf3dl2pvj8ldx4c1jcnk-bf-sde-9.5.0-kernel-modules-4.19.0-16-amd64/lib/modules/4.19.0-16-amd64/
total 16384
-r--r--r-- 1 nobody nogroup    34480 Jan  1  1970 bf_kdrv.ko
-r--r--r-- 1 nobody nogroup    62936 Jan  1  1970 bf_knet.ko
-r--r--r-- 1 nobody nogroup 16646848 Jan  1  1970 bf_kpkt.ko
```

Let's dig a bit deeper into the dependency tree.  The immediate
dependencies of the `packet-broker` package are

```
$ nix-store -q --references /nix/store/2aj27ji70991ij6g3pbvizczfcrazdw3-packet-broker-0.1
/nix/store/a3fc4zqaiak11jks9zd579mz5v0li8bg-bash-4.4-p23
/nix/store/w1m9bhgz32mwrfwx813krf85icknn3i7-packet_broker-artifacts-0.1
/nix/store/z2sngj8cl351chvsxxwd3pi6kp2nbg9g-bf-sde-accton-runtime-9.5.0
```

We have finally found the actual run-time environment provided by the
SDE package.  This derivation is the result of calling the
[`runtimeEnv'` support function](#runtimeEnvAux) with the argument
`accton_wedge100bf_32x`, which maps the platform identifier to the
baseboard identifier `accton` (provided by the reference BSP).  It's
dependencies are

```
$ nix-store -q --references /nix/store/z2sngj8cl351chvsxxwd3pi6kp2nbg9g-bf-sde-accton-runtime-9.5.0
/nix/store/hcrd7nv1ggayp4mw663aba0qb77s9mil-bf-sde-accton-runtime-env-9.5.0
/nix/store/4wgc1596a5i43wc1gny1djk3ndxsia9q-bf-tools-runtime-9.5.0
```

This is an example of a [_user environment_ introduced
earlier](#userEnvironment), a kind of meta-package. This means that it
provides no contents of its own. It merely collects the `bin`, `lib`
etc. directories from the packages on which it depends in a single
hierarchy with symbolic links. In this case, the environment contains
two packages: `bf-sde-accton-runtime-env-9.5.0` is itself an
environment and `bf-tools-runtime-9.5.0` provides the runtime utility
scripts

```
$ ls -l /nix/store/4wgc1596a5i43wc1gny1djk3ndxsia9q-bf-tools-runtime-9.5.0/bin/
total 8
-r-xr-xr-x 1 root root 519 Jan  1  1970 run_bfshell.sh
-r-xr-xr-x 1 root root 825 Jan  1  1970 run_switchd.sh
```

These scripts are wrapped inside shell scripts that set up the
enviornment, e.g.

```
$ grep SDE /nix/store/4wgc1596a5i43wc1gny1djk3ndxsia9q-bf-tools-runtime-9.5.0/bin/run_switchd.sh 
export SDE='/nix/store/hcrd7nv1ggayp4mw663aba0qb77s9mil-bf-sde-accton-runtime-env-9.5.0'
export SDE_INSTALL='/nix/store/hcrd7nv1ggayp4mw663aba0qb77s9mil-bf-sde-accton-runtime-env-9.5.0'
```

The `bf-sde-accton-runtime-env-9.5.0` package contains the runtime
version of the SDE itself, which, in turn, is composed of the set of
packages

```
$ nix-store -q --references /nix/store/hcrd7nv1ggayp4mw663aba0qb77s9mil-bf-sde-accton-runtime-env-9.5.0
/nix/store/4qnl1kirw5jh5jh3ndxhwyvvzx9bwawx-bf-sde-misc-components-9.5.0
/nix/store/jl2pqcxp8qq8j3ljkkjrbd842ncc1vxq-bf-syslibs-9.5.0
/nix/store/hjfrx08hd4az8wn1zc0zvgixxza30y05-bf-utils-9.5.0
/nix/store/p8iky1fwj6q5gbk519ccvba9vlsb6636-bf-platforms-accton-9.5.0
/nix/store/xz3v5fqdgpil50faa1963agjmb9swj1k-ptf-utils-9.5.0
/nix/store/y70c74xfh5gnxaaask1hf4pzlcgjlbkk-bf-drivers-runtime-9.5.0
```

This is how everything comes together in the end. It can't be stressed
enough that all of this is done automatically when `nix-build
packet-broker.nix` is executed. Missing dependencies, for example,
cannot happen with Nix.

### <a name="buildForModel"></a> Building for the Tofino Model

For illustration purposes, let's see how we can modify the build
recipe to create a version that runs on the Tofino ASIC emulation
instead of actual hardware.  We need to make only a few modifications

   * Select `model` as the target platform
   * Remove `requiredKernelModule`
   * Don't build a wrapper

The following expression does this:

```Nix
let
  pkgs = import ./. {};
  packet-broker = pkgs.bf-sde.latest.buildP4Program {
    pname = "packet-broker";
    version = "0.1";
    platform = "model";
    src = pkgs.fetchFromGitHub {
      owner = "alexandergall";
      repo = "packet-broker";
      rev = "366999";
      sha256 = "1rfm286mxkws8ra92xy4jwplmqq825xf3fhwary3lgvbb59zayr9";
    };
    p4Name = "packet_broker";
  };
in packet-broker
```

After building

```
$ nix-build packet-broker.nix
[...]
/nix/store/x61bsdzhz21axlpxgrf2q2kn6yrkr59f-packet-broker-0.1
```

it can be started just like before.  The script creates `veth`
interfaces to provide access to the virtual ports, starts the Tofino
model in the background and finally launches `bf_switchd`.

## <a name="packagingCP"></a>Packaging a Control-Plane Program for BfRuntime

BfRuntime is a customized version of
[p4runtime](https://github.com/p4lang/p4runtime). The SDE contains
`p4runtime` as third-party software in the `bf-drivers` source package
but it is not built by default and it is not included in the Nix
package.  In practice, BfRuntime is the primary interface between the
control- and data-plane components.

The `bf-drivers` package contains the Python bindings derived from the
[Google protobuf](https://developers.google.com/protocol-buffers)
specification of BfRuntime. It also contains a Python library called
`bfrt_grpc` to be used by gRPC clients.  This chapter explains how to
build a package for control-plane code which depends on `bfrt_grpc`.

There are two things that the packaging mechanism needs to take care
of.  The first is obvious: the location of `bfrt_grpc` must be added
to the module search path in order for the control-plane code to be
able to import the module. The second is a bit more intricate: the
current `bfrt_grpc` code (at least up to SDE 9.5.0) requires Python
2.7. Therefore, any code using the library must also be restricted to
that version.  The packaging should make sure that this condition is
satisfied (this also implies that the program doesn't make use of any
features not available in Python 2.7)

To illustrate how such a package could look like we make use of the
packet-broker once again.

### <a name="buildRecipeCP"></a>Writing the Build Recipe as a Nix Expression

The code for the broker's control-plane is located in the
[`control-plane`](https://github.com/alexandergall/packet-broker/tree/master/control-plane)
directory.  The `configd.py` script is the main program intended to
run as a daemon. An additional program `brokerctl` connects to the
daemon to interact with the control-plane from the command line
(e.g. to initiate a reload of the configuration, see the
[documentation](https://github.com/alexandergall/packet-broker/blob/master/README.md)
for details).  The `configd.py` script needs the `jsonschema` and
`ipaddress` modules as well as the `bfrt_grpc` module provided by the
`bf-drivers` package at runtime.  The daemon also uses a configuration
file in JSON and a schema to validate it.

Here is the Nix expression we're going to use to create the package

```nix
let
  pkgs = import ./. {};
  bf-drivers-runtime = pkgs.bf-sde.latest.pkgs.bf-drivers-runtime;
  python = bf-drivers-runtime.pythonModule;
in python.pkgs.buildPythonApplication {
  pname = "packet-broker-configd";
  version = "0.1";
  src = pkgs.fetchFromGitHub {
    owner = "alexandergall";
    repo = "packet-broker";
    rev = "366999";
    sha256 = "1rfm286mxkws8ra92xy4jwplmqq825xf3fhwary3lgvbb59zayr9";
  };

  propagatedBuildInputs = [
    bf-drivers-runtime
  ] ++ (with python.pkgs; [ jsonschema ipaddress ]);

  preConfigure = ''cd control-plane'';

  postInstall = ''
    mkdir -p $out/etc/packet-broker
    cp config.json schema.json $out/etc/packet-broker
  '';
}
```

We store it in the file `configd.nix`, again in the top-level
directory of `bf-sde-nixpkgs`.  The `pkgs` and `src` elements are the
same as for the P4 package. The line

```
  bf-drivers-runtime = pkgs.bf-sde.latest.pkgs.bf-drivers-runtime;
```

selects the `bf-drivers-runtime` package from the newest SDE
version. That package used a specific Python interpreter to build the
`bfrt_grpc` module, as mentioned in the introduction. It actually
makes that interpreter available through an attribute called
`pythonModule`.  The assignment

```
  python = bf-drivers-runtime.pythonModule;
```

picks it up to invoke the package build procedure later on.  This is
how we satisfy the constraint that our control-plane code uses the
correct Python version if it imports the `bfrt_grpc` module.

The rest of the expression is really just the application of the
standard [Nix tooling for
Python](https://nixos.org/manual/nixpkgs/stable/#python) and cannot be
covered here in detail.  In a nutshell, it uses `setuptools` with the
`bdist_wheel` method to create the scripts and modules specified by
`setup.py`.

Note that the `buildPythonApplication` in relation to the Python
package referenced by `python` works very much like the
`buildP4Program` function in relation to the SDE package as we've seen
in the previous chapter, i.e. it creates a package (our control-plane
program) based on another package (a specific Python interpreter).

One thing to note is how run-time dependencies of the package are
declared with the `propagatedBuildInputs` attribute.  Normally,
run-time dependencies are not specified explicitly for derivations in
Nix (they are determined automatically when the package is built).
However, this doesn't work with Python modules. What happens here,
essentially, is that Nix creates a Python environment containing the
modules specified by `porpagatedBuildInputs` and arranges for the
application (the `configd.py` script in this case) to be executed in
that environment.  For more information on this, refer to the section
on [specifying
dependencies](https://nixos.org/manual/nixpkgs/stable/#ssec-stdenv-dependencies)
and [Nix pill
20](https://nixos.org/guides/nix-pills/basic-dependencies-and-hooks.html).

### <a name="buildPackageCP"></a>Building the Package

This works exactly the same as for the P4 package

```
$ nix-build configd.nix
[ ... ]
/nix/store/ap8gfdykxdx7154asxyphhrqizjfbz47-packet-broker-configd-0.1
```

## <a name="usingPackagesWithProfile"></a>Using the Packages with a Nix Profile

The build procedures for the P4 and control-plane packages detailed in
the previous chapters are sufficient to make them usable.  For
instance, the packet-broker P4 program can be started simply by
executing

```
$ /nix/store/mkcbykv8rd0giwkc9q58q27hijn09rjn-packet_broker-module-wrapper/bin/packet_broker-module-wrapper
```

This is true for any Nix package: they can all be used directly from
`/nix/store`.  We could also use those paths directly in a `systemd`
unit file to create a service.  However, Nix offers a better mechanism
on top of the bare packages which also offers additional benefits.

This mechanism is called a
[profile](https://nixos.org/manual/nix/stable/#sec-profiles). It is
very similar to the [user environment](#userEnvironment) we have
already seen multiple times.  In fact, a profile is simply a
collection of user environments organized as a sequence of profile
_generations_.

Let's see what that means with our packet broker example. First we are
going to merge `configd.nix` with `packet-broker.nix` in a file
`pb.nix`:

```nix
{ kernelRelease }:

let
  pkgs = import ./. {};
  src = pkgs.fetchFromGitHub {
    owner = "alexandergall";
    repo = "packet-broker";
    rev = "366999";
    sha256 = "1rfm286mxkws8ra92xy4jwplmqq825xf3fhwary3lgvbb59zayr9";
  };
  bf-sde = pkgs.bf-sde.latest;
  version = "0.1";
  packet-broker = bf-sde.buildP4Program {
    pname = "packet-broker";
    platform = "accton_wedge100bf_32x";
    inherit version src;
    p4Name = "packet_broker";
    requiredKernelModule = "bf_kpkt";
  };
  bf-drivers-runtime = bf-sde.pkgs.bf-drivers-runtime;
  python = bf-drivers-runtime.pythonModule;
  configd = python.pkgs.buildPythonApplication {
    pname = "packet-broker-configd";
    inherit version src;

    propagatedBuildInputs = [
      bf-drivers-runtime
    ] ++ (with python.pkgs; [ jsonschema ipaddress ]);

    preConfigure = ''cd control-plane'';

    postInstall = ''
      mkdir -p $out/etc/packet-broker
      cp config.json schema.json $out/etc/packet-broker
    '';
  };
in {
  packet-broker = packet-broker.moduleWrapper kernelRelease;
  inherit configd;
}
```

The new expression evaluates to a set with attributes `packet-broker`
and `configd`.  This allows us to create both packages with a single
invocation of `nix-build`

```
$ nix-build pb.nix --argstr kernelRelease $(uname -r)
/nix/store/ap8gfdykxdx7154asxyphhrqizjfbz47-packet-broker-configd-0.1
/nix/store/9j1bpjif9qcnzzy4jrh9bdk17vwp9r4c-packet_broker-module-wrapper

```

Next we're going to create a profile containing these two packages.
This could be done by any user, but a good choice for a global
installation is to create it as root

```
# nix-env -f pb.nix -p /nix/var/nix/profiles/packet-broker -i -r --argstr kernelRelease $(uname -r)
building '/nix/store/dly3kq5nsaz9sxqz62hfrvn7hgwcd4q2-user-environment.drv'...
created 6 symlinks in user environment
```

A profile can be located anywhere but unless it's somewhere underneath
`/nix/var/nix/profiles`, it won't become a [garbage collection
root](#gc). So, what have we got now?

```
$ ls -l /nix/var/nix/profiles/packet-broker*
lrwxrwxrwx 1 root root 20 Jun 11 16:24 /nix/var/nix/profiles/packet-broker -> packet-broker-1-link
lrwxrwxrwx 1 root root 60 Jun 11 16:24 /nix/var/nix/profiles/packet-broker-1-link -> /nix/store/9ij1vlfn43dvch3ddwzn7j40djrbnwkm-user-environment
```

This nicely collects the artifacts of the packages in a single location. It
also provides easy rollback to previous versions.

### <a name="gc"></a>Profile Generations and Garbage Collection

Nix creates a new generation of the profile each time we execute
`nix-env -i` with a new version of the packages. Generations are never
deleted automatically.  As a side-effect, any package referred by a
profile is protected from deletion, irrespective of whether the
generation of the profile is the current one or not.

What this means is the following.  Nix treats packages like a memory
management system using a garbage collector.  It keeps a list of
_garbage collection roots_ and treats every package as being _alive_
which is referenced by such a root (directly or indirectly).

The command `nix-collect-garbage` (which can be called by any user)
deletes all packages from `/nix/store` which are not alive and
`nix-store --delete <path>` deletes a specific package unless it is
alive or is a dependency of another package.  Those are actually the
only ways to remove anything from the Nix store.

One way to create a garbage collection root is with `nix-build`.  In
our example, when we executed, for example, `nix-build
packet-broker.nix`, you might have noticed that there appears a
symbolic link called `result` in the current directory pointing to the
package

```
$ nix-build packet-broker.nix --argstr kernelRelease $(uname -r)
/nix/store/xyv33rlrk46yw9ix1kfdjr4i09s6j2bj-packet_broker-module-wrapper
gall@spare-PB1:~/bf-sde-nixpkgs$ ls -l result
lrwxrwxrwx 1 gall gall 72 Apr 27 14:51 result -> /nix/store/xyv33rlrk46yw9ix1kfdjr4i09s6j2bj-packet_broker-module-wrapper
```

This link is registered as a garbage collection root.  So an attempt
to delete it fails

```
$ nix-store --delete /nix/store/xyv33rlrk46yw9ix1kfdjr4i09s6j2bj-packet_broker-module-wrapper
finding garbage collector roots...
0 store paths deleted, 0.00 MiB freed
error: cannot delete path '/nix/store/xyv33rlrk46yw9ix1kfdjr4i09s6j2bj-packet_broker-module-wrapper' since it is still alive
```

The second way to create a garbage collection root is through
profiles.  Every generation of a profile is automatically registered as
a root.  In our case

```
$ nix-store --gc --print-roots | grep packet-broker
/nix/var/nix/profiles/packet-broker-1-link -> /nix/store/d29aiqfr74rcdghvp2p3f3aqxj2lccmd-user-environment
```

Generations of a profile can be manipulated with the
`--list-generations`, `--switch-generation` and `--delete-generations`
sub-commands of `nix-env`.

If storage is a concern, you should make sure to remove profile
generations which are no longer needed and run `nix-collect-garbage`
to remove unneeded packages from `/nix/store`.

## <a name="deploymentModels"></a>Deployment Models

I this section, the term _deployment_ specifically refers to the
mechanism of instantiating the packages required for a particular
service in `/nix/store`.  In the packet broker example, this would be
the packages `packet_broker-module-wrapper` and `configd` and all
their recursive runtime dependencies.

In theory, a pure source deployment of all packages is possible but
clearly not practical.  Nix uses a concept called _substitution_ to
make use of pre-built packages.  Before a package is actually built,
Nix first creates a description of the build process called
_derivation_.  The derivation contains, among other things, the
so-called _output path_ of the package, which is the location in
`/nix/store` where the final package will be stored, for example

```
/nix/store/bsz947wniwh1wrwb5dn45h6kgvs8wssa-packet_broker-module-wrapper
```

This information is know _before_ the package is built. Nix can be
configured with URLs pointing to servers, each of which provides a
`/nix/store` with pre-built packages called _binary caches_.  If this
is done, the build process will check whether the output path already
exist on any of these caches before building the package.  If found,
it simply fetches the package from the remote host and adds it to the
local `/nix/store`.  This process is known as substitution, because
the nature of Nix guarantees that if the hash in the store path on the
remote system is the same as we expect to build locally, the packages
must be identical.

Any standard installation of Nix uses at least one such binary cache,
usually https://cache.nixos.org. This cache serves all packages built
from official releases of the [`nixpkgs`
collection](https://github.com/NixOS/nixpkgs).

This mechanism essentially turns the source-deployment into _binary
deployment_.

The `bf-sde-nixpkgs` repository uses one of these `nixpkgs` releases
as the base system for the SDE packages.  This can be seen in `default.nix`:

```
{ overlays ? [], ... } @attrs:

let
  nixpkgs = (fetchTarball https://github.com/NixOS/nixpkgs/archive/20.09-1181-gfee7f3fcb41.tar.gz);
in import nixpkgs ( attrs // {
  overlays = import ./overlay.nix ++ overlays;
})

```

In this case, it uses commit `fee7f3` on the `20.09` release branch.
As a consequence, most of the packages can be substituted from the
standard binary cache.  However, all SDE-specific packages as well as
those whose build recipes are overridden by `bf-sde-nixpkgs` (e.g. to
change build options or up- or down grade versions) are not available
from the cache and need to be built from source.  This limitation can
be mitigated by building a separate binary cache for these packages.
This is really a hybrid between source and binary deployment.

### <a name="sourceDeployment"></a>Source Deployment

This is the most direct deployment model and the one we have been
using in the packet broker example up to now.  In this model, we start
with a specific version of the the `bf-sde-nixpkgs` Git repository and
build the desired packages either with `nix-build` (or `nix-env` in
case we want to create a Nix profile as well).  As mentioned in the
introduction to this section, this is really just a source deployment
with regard to the SDE packages (and modified standard packages). All
standard packages are fetched from the binary cache.

Apart from the time and hardware resources it takes to build the SDE
from source, this model also poses a legal problem, because it
requires access to the SDE itself, which is currently only possible by
entering an NDA with Intel.  This would make it impossible for third
parties to use the packages.

### <a name="binaryDeploymentNoCache"></a>Binary Deployment without a Cache

Nix makes pure binary deployment of packages very easy due to its
declarative nature and strict dependency management.  Key to this is
the concept of the _closure_ of a package.  The closure is the
complete set of recursive dependencies of the package.  In our
example, the closure of the `packet-broker` package can
be obtained with

```

$ nix-store -qR $(nix-build pb.nix --argstr kernelRelease $(uname -r))
[...]
/nix/store/jqnprhfrsbl2girajpwhcv45qd8ij5lv-procps-3.3.16
/nix/store/yvl77j0zv2jdyblsi4h5ai0zr4q8l9kw-packet-broker-0.1
/nix/store/xyv33rlrk46yw9ix1kfdjr4i09s6j2bj-packet_broker-module-wrapper
```

This closure contains around 100 packages. It sounds like a lot but
remember that it contains the indirect dependencies as well.
Furthermore it is completely self-contained: there are no dependencies
outside `/nix/store`. Also, many of the packages in the closure are
shared by other packages.  The closure has an extremely useful
property: if it is copied to `/nix/store` on _any_ system with Nix
installed, the package is guaranteed to work.

Nix provides a method to extract the entire closure as a single file:

```
$ nix-store --export $(nix-store -qR $(nix-build pb.nix --argstr kernelRelease $(uname -r))) >closure
```

To install it to `/nix/store` on another system, copy `closure` and
execute

```
# nix-store --import <closure
```

Note that this has to be done by the `root` user unless the closure is
digitally signed (which is not covered here).

Due to the manner in which the SDE packages have been constructed,
this closure does not contain any components which would fall under
the NDA with Intel, hence it can be safely distributed to third
parties.

Also note that the Nix expression language is not used when installing
the closure on the target system, i.e. the Nix expression that defines
our application (from the `pb.nix` file in this example) is not needed
at all.

### <a name="binaryDeploymentCache"></a>Binary Deployment with a Cache

Explicit distribution of the closure as described in the previous
chapter may work in single-instance or small-scale deployments but
could become somewhat unpractical on a larger scale.  Nix supports a
standard mechanism to use a Nix store on a remote server as a
repository for pre-built packages, referred to as a _binary cache_.
How such a cache is populated and made accessible is outside the scope
of this documentation.  The reader is referred to the [NixOS
wiki](https://nixos.wiki/wiki/Binary_Cache) and the
[Cachix](https://cachix.org/) project.

For the purpose of SDE-based packages, it is assumed that the provider
of a particular service like the packet broker, has set up such a
cache and populated it with the closure discussed previously.  It is
important that the Nix store on that cache does **not** contain any of
the SDE components covered by the NDA.

Once that cache is set up, the administrator creates a key-pair used to
sign the packages being downloaded from the cache.  The public key is
published together with the URL where the cache can be reached, for
example https://cache.exmple.net. To use the cache, add the following
lines to `/etc/nix/nix.conf`

```
extra-substituters = https://cache.example.net
trusted-substituters = https://cache.example.net
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= cache.example.net:<public key>
```

Then restart the `nix-daemon` server with `systemctl restart
nix-daemon` for the change to take effect. Note that the standard
binary cache https://cache.nixos.org is registered by default and so
is it's public key. But when we add the key of the new cache to
`trusted-public-keys`, we also have to specify the key for
`cache.nixos.org` to preserve the default.

Once this is done, we can execute the `nix-build` and `nix-env`
commands [discussed before](deploymentWithProfile) to deploy the
service and Nix will fetch the missing parts of the closure from the
cache.
