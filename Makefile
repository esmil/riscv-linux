# Copyright (c) 2020, Emil Renner Berthing
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
# OF SUCH DAMAGE.

MAKEFLAGS += rR
c := ,

CP = cp
RM_RF = rm -rf
GIT = git
SSH = ssh
SHELLCHECK = shellcheck
DOWNLOAD = curl -\#Lo

URL = https://esmil.dk/riscv-linux

TOOLCHAIN_BARE  = riscv64-unknown-elf-
TOOLCHAIN_LINUX = riscv64-linux-gnu-

OPENSBI_DIR = opensbi
OPENSBI_GITURL = https://github.com/riscv/opensbi.git
OPENSBI_PLATFORM = generic
OPENSBI_TOOLCHAIN = $(TOOLCHAIN_LINUX)

UBOOT_DIR = u-boot
UBOOT_GITURL = https://gitlab.denx.de/u-boot/u-boot.git
UBOOT_DEFCONFIG = qemu-riscv64_spl_defconfig
UBOOT_TOOLCHAIN = $(TOOLCHAIN_LINUX)

QEMU_RV64 = qemu-system-riscv64
QEMU_RV32 = qemu-system-riscv32
QEMU_IMG = qemu-img
QEMU_MACHINE = virt
QEMU_MEMORY = 1G
QEMU_SMP = 2
QEMU_BIOS = fw_jump.bin
QEMU_KERNEL = Image

SSH_HOST = 127.0.0.1
SSH_PORT = 2222
SSH_USER = root
SSH_KEY = qemu.key

virtio-blk-mmio =\
	-drive 'id=$1,if=none,$(or $3,discard=unmap$cdetect-zeroes=unmap),file=$2' \
	-device 'virtio-blk-device,drive=$1'
virtio-blk-pci =\
	-drive 'id=$1,if=none,$(or $3,discard=unmap$cdetect-zeroes=unmap),file=$2' \
	-device 'virtio-blk-pci,drive=$1'

# this must be preceeded by a scsi device
# eg.: -device virtio-scsi-device,id=scsi0
scsi-hd =\
	-drive 'id=$1,if=none,$(or $3,discard=unmap$cdetect-zeroes=unmap),file=$2' \
	-device 'scsi-hd,device_id=$1,drive=$1'

NEW_IMAGE = /tmp/new.qcow2
NEW_SIZE = 10G

ifdef V
E := @\#
Q :=
else
E := @echo
Q := @
endif

.PHONY: run ssh download wget check opensbi clean disclean

run: rawhide

ssh:
	$Q$(SSH) -p $(SSH_PORT) -i $(SSH_KEY) -o StrictHostKeyChecking=no $(SSH_USER)@$(SSH_HOST)

download: fw_jump.bin Image rawhide-rv64.qcow2 sid-rv64.qcow2

wget: DOWNLOAD = wget --show-progress -qO
wget: download

check: bootstrap.sh
	$E '  CHECK   $^'
	$Q$(SHELLCHECK) $<

rawhide sid: %: %.qcow2 $(QEMU_BIOS) $(QEMU_KERNEL)
	$E 'Running QEMU. Press Ctrl-a,c,q,<enter> to exit.'
	$Q$(QEMU_RV64) \
	  -nographic \
	  -machine $(QEMU_MACHINE) \
	  -m $(QEMU_MEMORY) \
	  -smp $(QEMU_SMP) \
	  -bios $(QEMU_BIOS) \
	  -kernel $(QEMU_KERNEL) \
	  -append 'earlycon root=/dev/sda rootfstype=btrfs ro rootflags=ssd,subvol=/$@ rootwait' \
	  -device virtio-rng-device \
	  -object cryptodev-backend-builtin,id=cryptdev0 \
	  -device virtio-crypto-pci,id=crypt0,cryptodev=cryptdev0 \
	  -netdev user,id=net0,ipv4=on,ipv6=off,hostfwd=tcp::$(SSH_PORT)-:22 \
	  -device virtio-net-device,netdev=net0 \
	  -device virtio-scsi-device,id=scsi0 \
	  $(call scsi-hd,hd0,$<)

new-rawhide new-sid: new-%: %.qcow2 $(NEW_IMAGE) $(QEMU_BIOS) $(QEMU_KERNEL)
	$E 'Running QEMU. Press Ctrl-a,c,q,<enter> to exit.'
	$Q$(QEMU_RV64) \
	  -nographic \
	  -machine $(QEMU_MACHINE) \
	  -m $(QEMU_MEMORY) \
	  -smp $(QEMU_SMP) \
	  -bios $(QEMU_BIOS) \
	  -kernel $(QEMU_KERNEL) \
	  -append 'earlycon root=/dev/sda rootfstype=btrfs ro rootflags=ssd,subvol=/$(@:new-%=%) rootwait' \
	  -device virtio-rng-device \
	  -object cryptodev-backend-builtin,id=cryptdev0 \
	  -device virtio-crypto-pci,id=crypt0,cryptodev=cryptdev0 \
	  -netdev user,id=net0,ipv4=on,ipv6=off,hostfwd=tcp::$(SSH_PORT)-:22 \
	  -device virtio-net-device,netdev=net0 \
	  -device virtio-scsi-device,id=scsi0 \
	  $(call scsi-hd,hd0,$<) \
	  $(call scsi-hd,hd1,$(NEW_IMAGE))

test-rawhide test-sid: $(NEW_IMAGE)
	$E 'Running QEMU. Press Ctrl-a,c,q,<enter> to exit.'
	$Q$(QEMU_RV64) \
	  -nographic \
	  -machine $(QEMU_MACHINE) \
	  -m $(QEMU_MEMORY) \
	  -smp $(QEMU_SMP) \
	  -bios $(QEMU_BIOS) \
	  -kernel $(QEMU_KERNEL) \
	  -append 'earlycon root=/dev/sda rootfstype=btrfs ro rootflags=ssd,subvol=/$(@:test-%=%) rootwait' \
	  -device virtio-rng-device \
	  -object cryptodev-backend-builtin,id=cryptdev0 \
	  -device virtio-crypto-pci,id=crypt0,cryptodev=cryptdev0 \
	  -netdev user,id=net0,ipv4=on,ipv6=off,hostfwd=tcp::$(SSH_PORT)-:22 \
	  -device virtio-net-device,netdev=net0 \
	  -device virtio-scsi-device,id=scsi0 \
	  $(call scsi-hd,hd0,$<,snapshot=on)

run-uboot:
	$E 'Running QEMU. Press Ctrl-a,c,q,<enter> to exit.'
	$Q$(QEMU_RV64) \
	  -nographic \
	  -machine $(QEMU_MACHINE) \
	  -m $(QEMU_MEMORY) \
	  -bios u-boot-spl \
	  -device loader,file=u-boot.itb,addr=0x80200000 \
	  -device virtio-rng-device \
	  -netdev user,id=net0,ipv4=on,ipv6=off,hostfwd=tcp::$(SSH_PORT)-:22 \
	  -device virtio-net-device,netdev=net0

uboot: $(UBOOT_DIR)/spl/u-boot-spl $(UBOOT_DIR)/u-boot.itb
	$E '  CP      $^'
	$Q$(CP) $^ .

opensbi: $(OPENSBI_DIR)/build/platform/generic/firmware/fw_jump.bin $(OPENSBI_DIR)/build/platform/generic/firmware/fw_dynamic.bin
	$E '  CP       $^'
	$Q$(CP) $^ .

$(NEW_IMAGE):
	$E '  QEMU_IMG $@'
	$Q$(QEMU_IMG) create -f qcow2 $@ $(NEW_SIZE)

rawhide.qcow2 sid.qcow2 new.qcow2: %.qcow2: %-rv64.qcow2
	$E '  QEMU_IMG $@'
	$Q$(QEMU_IMG) create -f qcow2 -b $< -F qcow2 $@

fw_jump.bin Image rawhide-rv64.qcow2 sid-rv64.qcow2:
	$E 'Downloading $@..'
	$Q$(DOWNLOAD) '$@' '$(URL)/$@'

$(UBOOT_DIR)/fw_dynamic.bin: fw_dynamic.bin | $(UBOOT_DIR)/
	$E '  CP       $@'
	$Q$(CP) $< $@

$(UBOOT_DIR)/spl/u-boot-spl $(UBOOT_DIR)/u-boot.itb: $(UBOOT_DIR)/.config $(UBOOT_DIR)/fw_dynamic.bin
	$Q$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(UBOOT_TOOLCHAIN)

$(UBOOT_DIR)/.config: | $(UBOOT_DIR)/
	$Q$(MAKE) -C $(UBOOT_DIR) CROSS_COMPILE=$(UBOOT_TOOLCHAIN) $(UBOOT_DEFCONFIG)

$(OPENSBI_DIR)/build/platform/generic/firmware/fw_jump.bin $(OPENSBI_DIR)/build/platform/generic/firmware/fw_dynamic.bin: | $(OPENSBI_DIR)/
	$Q$(MAKE) -C $(OPENSBI_DIR) CROSS_COMPILE=$(OPENSBI_TOOLCHAIN) PLATFORM=$(OPENSBI_PLATFORM)

$(UBOOT_DIR)/:
	$Q$(GIT) clone $(UBOOT_GITURL) $(UBOOT_DIR)

$(OPENSBI_DIR)/:
	$Q$(GIT) clone $(OPENSBI_GITURL) $(OPENSBI_DIR)

clean:
	$Qtest ! -d $(OPENSBI_DIR) || $(MAKE) -C $(OPENSBI_DIR) distclean
	$Qtest ! -d $(UBOOT_DIR) || $(MAKE) -C $(UBOOT_DIR) distclean
	$E '  RM       $(NEW_IMAGE)'
	$Q$(RM_RF) '$(NEW_IMAGE)'

distclean:
	$Q$(RM_RF) $(OPENSBI_DIR) $(UBOOT_DIR)
