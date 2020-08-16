# riscv-linux

## What is this?

This is a quick way to get [RISC-V][riscv] Linux running in [Qemu][qemu].

[riscv]: https://riscv.org/
[qemu]: https://www.qemu.org/

## Installing Qemu

Most modern Linux distrubutions have Qemu packaged, but often the RISC-V version
is split into a separate package such as `qemu-system-misc`, `qemu-arch-extra` or
even `qemu-system-riscv`.

On MacOS the Qemu is packaged in [homebrew][] and includes RISC-V versions.

[homebrew]: https://brew.sh/

## Using it

To run a Fedora Rawhide type
```sh
make rawhide
```

To run a Debian Sid type
```sh
make sid
```

This will automatically download the needed files from https://esmil.dk/riscv-linux

- `fw_jump.bin`: OpenSBI early initialization code running in machine mode
- `Image`: The Linux kernel
- `rawhide.qcow2`/`sid.qcow2`: Root filesystem

Once it finishes booting you can either login directly or ssh into it from another
terminal using
```sh
make ssh
```

The root password is `123`.

## OpenSBI

Qemu emulates the 3 modes defined in the priviledged spec for RISC-V: machine-,
supervisor- and user mode. The Linux kernel is meant to run in supervisor mode,
and call into machine mode for a few functions using the
*Supervisor Binary Interface*. [OpenSBI][opensbi] implements these functions in
machine mode and some early code to set up the machine, switch to supervisor mode
and jump to the Linux kernel. This is the `-bios fw_jump.bin` option to Qemu.

You can cross-compile your own `fw_jump.bin` using
```sh
make opensbi
```

For this you'll of course need a RISC-V toolchain. Luckily OpenSBI can be compiled
both using a toolchain for 'bare metal', usually prefixed with `riscv64-unknown-elf-`,
or a toolchain for Linux, usually prefixed with `riscv64-linux-gnu-`.

[opensbi]: https://github.com/riscv/opensbi

## Kernel

If you have a working RISC-V toolchain it is actually quite easy to cross-compile the
Linux kernel. Just enter the Linux source tree and type

```sh
make -j8 ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig
make -j8 ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- all
```

This gives you a working kernel in `arch/riscv/boot/Image`. However it's a big and generic
kernel so it'll take a while to compile. You can build a smaller kernel more specialized 
for the Qemu virtial machine using the config in this repo:

```sh
cp /path/to/riscv-linux/config-virt .config
make -j8 ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- oldconfig
# optionally configure it further
#make -j8 ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- nconfig
make -j8 ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- all
```

The default kernel this repo downloads is built using this `config-virt` configuration
on the `riscv` branch in [https://github.com/esmil/linux][riscv-repo].
For now this is the latest stable kernel + the new RISC-V bits that will land in the
next release.

[riscv-repo]: https://github.com/esmil/linux/tree/riscv

## Images

The images downloaded are built using the `bootstrap.sh` script in this repo. These
installations are meant to be small and are quite opinionated. As an example they
use `systemd-networkd` to manage the network rather than the usual `networkmanager` or
`ifupdown` scripts. So don't worry if they feel "alien", it has nothing to do 
with RISC-V. You can just download the regular but much larger distro-built images
directly from the [Fedora][fedora-images] and [Debian][debian-images] sites.

[fedora-images]: https://dl.fedoraproject.org/pub/alt/risc-v/repo/virt-builder-images/images/
[debian-images]: https://people.debian.org/~gio/dqib/

## License

This project is licensed under the [BSD 3-Clause][bsd-3] license.

[bsd-3]: https://opensource.org/licenses/BSD-3-Clause
