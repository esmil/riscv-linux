#!/bin/bash
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

set -e -o pipefail

join() { local IFS="$1"; shift; echo "$*"; }

# shellcheck disable=SC1091
distroid="$(. /etc/os-release; echo "$ID")"
case "$distroid" in
fedora) distro=rawhide;;
debian) distro=sid;;
esac
hostname="${distro}-rv64"
# shellcheck disable=SC2016
password='$5$PasswordIs123$tBHaACgKswy0l2YDAmbPdQDaNofCA90AZgdc3waeHV0'
rootfs=btrfs
rootmnt=/mnt
locale='en_US.UTF-8'

pkg_install=(
  sudo
  man-db
  findutils
  openssh-server
)
systemd_mask=(
  'serial-getty@hvc0.service'
)
systemd_disable=(
  'getty@tty1.service'
)
systemd_enable=(
  'systemd-resolved.service'
  'systemd-networkd.service'
)

readonly usage="
Usage: $0 -d <dest> [<options>]

Options:
    -d <dest>        Bootstrap into this directory or block device. Required.
    -D <distro>      Set distribution to instal. Defaults to $distro
                     Valid opions: rawhide, sid
    -R <rootfs>      Use this root filesystem. Defaults to $rootfs
                     Valid opions: efi-btrfs, btrfs, efi-ext4, ext4
    -r <rootmnt>     Mount root filesystem here. Defaults to $rootmnt
    -H <hostname>    Set hostname of bootstrapped machine. Defaults to $hostname
    -i <pkg>         Add extra package to install. May be specified multiple times.
    -h               Show this help.
"

while getopts 'd:D:R:r:H:i:h' opt; do
  case "$opt" in
  d) dest="$OPTARG";;
  D) distro="$OPTARG";;
  R) rootfs="$OPTARG";;
  r) rootmnt="$OPTARG";;
  H) hostname="$OPTARG";;
  i) pkg_install+=("$OPTARG");;
  h)
    echo 'Bootstrap a new RISC-V 64bit Linux.'
    echo "$usage"
    exit 0;;
  *)
    echo "$usage" >&2
    exit 1;;
  esac
done
shift $((OPTIND-1))

if [[ -z "$dest" ]]; then
  echo 'No destination specified.' >&2
  echo "$usage" >&2
  exit 1
elif [[ -b "$dest" ]]; then
  device="$dest"
  dest=''
elif [[ -d "$dest" ]]; then
  :
else
  echo "Destination '$dest' is neither a block device or directory." >&2
  exit 1
fi

set -x

if [[ -n "$device" ]]; then
  case "$rootfs" in
  efi-*)
    pkg_install+=('dosfstools')
    case "$device" in
    *0|*1|*2|*3|*4|*5|*6|*7|*8|*9)
      efidev="${device}p1"
      rootdev="${device}p2"
      ;;
    *)
      efidev="${device}1"
      rootdev="${device}2"
      ;;
    esac
    [[ -n "$efimb" ]] || efimb=511
    [[ -n "$efiflags" ]] || efiflags='defaults,noauto,x-systemd.automount,x-systemd.idle-timeout=2min,x-systemd.device-timeout=5min,noatime,utf8,iocharset=iso8859-15,fmask=0133,dmask=0022,errors=remount-ro'

    {
      echo 'label: gpt'
      echo 'unit: sectors'
      echo 'sector-size: 512'
      echo "start=2048, size=$((efimb*2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=\"EFI\""
      echo "start=$((2048 + efimb*2048)), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"BTRFS\""
    } | sfdisk "$device"
    mkfs.vfat -v -F32 -n EFI "$efidev"
    ;;
  *)
    rootdev="$device"
    ;;
  esac
  case "$rootfs" in
  *btrfs)
    pkg_install+=('btrfs-progs')
    [[ -n "$rootsub" ]] || rootsub="$distro"
    [[ -n "$rootflags" ]] || rootflags='defaults,noatime,ssd'

    mkfs.btrfs -m single -d single -L BTRFS "$rootdev"
    mount -t btrfs -o "$rootflags,subvol=/" "$rootdev" "$rootmnt"
    chmod 755 "$rootmnt"
    btrfs sub create "$rootmnt/home"
    btrfs sub create "$rootmnt/$rootsub"
    dest="$rootmnt/$rootsub"
    ;;
  *ext4)
    pkg_install+=('e2fsprogs')
    [[ -n "$rootflags" ]] || rootflags='defaults'

    mkfs.ext4 -v -L ROOT "$rootdev"
    mount -t ext4 -o "$rootflags" "$rootdev" "$rootmnt"
    chmod 755 "$rootmnt"
    dest="$rootmnt"
    ;;
  *)
    echo "Unsupported filesystem '$rootfs'." >&2
    exit 1
    ;;
  esac
fi

case "$distro" in
rawhide)
  readonly repo='rawhide-riscv-koji'
  pkg_install+=(
    systemd-udev
    systemd-networkd
    glibc-langpack-${locale%%_*}
    passwd
    vim-enhanced
    iproute
    iputils
    openssh-clients
    dnf
    'dnf-command(leaves)'
  )
  systemd_mask+=(
    'systemd-homed.service'
    'systemd-userdbd.socket'
    'systemd-userdbd.service'
  )
  systemd_disable+=(
    'dnf-makecache.timer'
  )
  systemd_enable+=(
    'sshd'
  )

  if [[ ! -d "$dest/etc" ]]; then
    dnf \
      --assumeyes \
      --setopt='install_weak_deps=False' \
      --installroot="$dest" \
      --releasever=rawhide \
      --disablerepo='*' \
      --enablerepo="$repo" \
      install "${pkg_install[@]}"

    chmod 755 "$dest"
  fi
  if [[ -n "$efidev" ]]; then
    mount -t vfat -o "$efiflags" "$efidev" "$dest/boot"
  fi

  for i in "$dest"/etc/yum.repos.d/*.repo; do
    sed -i -e 's/^enabled=1/enabled=0/' "$i"
  done

  {
    echo "[$repo]"
    echo 'name=Rawhide RISC-V Koji'
    # shellcheck disable=SC2016
    echo 'baseurl=http://fedora.riscv.rocks/repos/rawhide/latest/$basearch/'
    echo 'enabled=1'
    echo 'gpgcheck=0'
  } | install -o root -g root -m644 /dev/stdin "$dest/etc/yum.repos.d/${repo}.repo"

  echo 'install_weak_deps=False' >> "$dest/etc/dnf/dnf.conf"

  {
    echo 'set -e -o pipefail'
    echo 'set -x'
    echo 'dnf clean all'
    for i in "${systemd_disable[@]}"; do
      echo "systemctl disable '$i'"
    done
    for i in "${systemd_mask[@]}"; do
      echo "systemctl mask '$i'"
    done
    for i in "${systemd_enable[@]}"; do
      echo "systemctl enable '$i'"
    done
    echo "echo 'root:$password' | chpasswd -e"
  } | chroot "$dest" bash -

  sed -i \
    -e '/^netgroup:/b;/^hosts:/{h;s/^/#/;p;g;s/files .*/files resolve/;b};/^[a-z][a-z]*:/s/ sss *//' \
    "$dest/etc/nsswitch.conf"
  rm -f "$dest/etc/nsswitch.conf.bak"

  ln -s /dev/null "$dest/etc/udev/rules.d/60-block-scheduler.rules"

  {
    echo 'set mouse='
    echo 'set ttymouse='
  } | install -o root -g root -m644 /dev/stdin "$dest/etc/vimrc.local"
  ;;
sid)
  mirror="https://deb.debian.org/debian-ports/"
  suite=sid
  components=(main)
  pkg_exclude=(
    apt-transport-https
    gcc-9-base
  )
  pkg_include=(
    debian-ports-archive-keyring
    ca-certificates
    apt-utils
    dialog
  )
  pkg_install+=(
    udev
    locales
    dbus-broker
    dbus-user-session
    deborphan
    libnss-resolve
    iproute2
    vim
    less
  )
  #systemd_mask+=()
  systemd_disable+=(
    'e2scrub_all.timer'
    'apt-daily-upgrade.timer'
    'apt-daily.timer'
    'e2scrub_reap.service'
    'systemd-timesyncd.service'
  )
  systemd_enable+=(
    'ssh'
  )

  if [[ ! -d "$dest/etc" ]]; then
    debootstrap \
      --variant=minbase \
      --components="$(join , "${components[@]}")" \
      --keyring=/usr/share/keyrings/debian-ports-archive-keyring.gpg \
      --exclude="$(join , "${pkg_exclude[@]}")" \
      --include="$(join , "${pkg_include[@]}")" \
      "$suite" "$dest" "$mirror"

    chmod 755 "$dest"
  fi
  if [[ -n "$efidev" ]]; then
    mount -t vfat -o "$efiflags" "$efidev" "$dest/boot"
  fi

  # don't automatically enable/start installed daemons
  echo 'exit 101' | install -o root -g root -m755 /dev/stdin "$dest/usr/sbin/policy-rc.d"

  # don't automatically install recommended and suggested packages
  {
    echo 'APT::Install-Recommends "0";'
    echo 'APT::Install-Suggests "0";'
  } | install -o root -g root -m644 /dev/stdin "$dest/etc/apt/apt.conf.d/06norecommends"

  # create /etc/apt/sources.list
  {
    echo "deb $mirror sid ${components[*]}"
    echo "deb $mirror unreleased ${components[*]}"
    echo "#deb-src $mirror sid ${components[*]}"
  } | install -o root -g root -m644 /dev/stdin "$dest/etc/apt/sources.list"

  {
    echo 'set -e -o pipefail'
    echo 'set -x'

    echo 'export LC_ALL=C'
    echo 'export DEBIAN_FRONTEND=noninteractive'

    echo '{'
    echo "  echo 'locales locales/locales_to_be_generated multiselect $locale ${locale##*.}'"
    echo "  echo 'locales locales/default_environment_locale select $locale'"
    echo '} | debconf-set-selections'

    echo 'apt-get -y update'

    echo 'mkdir /tmp/fake'
    echo 'ln -s /bin/true /tmp/fake/initctl'
    echo 'ln -s /bin/true /tmp/fake/invoke-rc.d'
    echo 'ln -s /bin/true /tmp/fake/restart'
    echo 'ln -s /bin/true /tmp/fake/start'
    echo 'ln -s /bin/true /tmp/fake/stop'
    echo 'ln -s /bin/true /tmp/fake/start-stop-daemon'
    echo 'ln -s /bin/true /tmp/fake/service'
    # shellcheck disable=SC2016
    echo 'OLDPATH="$PATH"'
    # shellcheck disable=SC2016
    echo 'export PATH="/tmp/fake:$PATH"'

    echo "apt-get -y -o 'Dpkg::Options::=--force-confnew' dist-upgrade"
    echo "apt-get -y install ${pkg_install[*]}"
    echo 'apt-get clean'

    # shellcheck disable=SC2016
    echo 'export PATH="$OLDPATH"'
    echo 'rm -rf /tmp/fake'

    for i in "${systemd_disable[@]}"; do
      echo "systemctl disable '$i'"
    done
    for i in "${systemd_mask[@]}"; do
      echo "systemctl mask '$i'"
    done
    for i in "${systemd_enable[@]}"; do
      echo "systemctl enable '$i'"
    done
    echo "echo 'root:$password' | chpasswd -e"
  } | chroot "$dest" bash -

  ln -fs /etc/locale.conf "$dest/etc/default/locale"

  {
    echo 'set mouse='
    echo 'set ttymouse='
  } | install -o root -g root -m644 /dev/stdin "$dest/etc/vim/vimrc.local"
  ;;
esac

if [[ -n "$hostname" ]]; then
  echo "$hostname" | install -o root -g root -m644 /dev/stdin "$dest/etc/hostname"
fi

if [[ -n "$rootdev" ]]; then
  {
    rootuuid="$(blkid -s UUID -o value "$rootdev")"
    if [[ -n "$efidev" ]]; then
      efiuuid="$(blkid -s UUID -o value "$efidev")"
      echo "UUID=$efiuuid /boot vfat $efiflags 0 2"
      echo
    fi
    case "$rootfs" in
    *btrfs)
      echo "UUID=$rootuuid /     btrfs $rootflags,subvol=/$rootsub 0 1"
      echo "UUID=$rootuuid /home btrfs $rootflags,subvol=/home 0 2"
      echo "UUID=$rootuuid /mnt  btrfs $rootflags,subvol=/ 0 2"
      ;;
    *ext4)
      echo "UUID=$rootuuid / ext4 $rootflags 0 1"
      ;;
    esac
  } | install -o root -g root -m644 /dev/stdin "$dest/etc/fstab"

  case "$rootfs" in
  *btrfs)
    ln -s /mnt "$dest/var/lib/machines"
    ln -s /mnt "$dest/var/lib/portables"
    ;;
  esac
fi

## Allow root to login with just a password
#sed -i \
#  -e '/^#*PermitRootLogin/cPermitRootLogin yes' \
#  -e '/^#*PasswordAuthentication/cPasswordAuthentication yes' \
#  -e '/^#*UsePAM/cUsePAM yes' \
#  "$dest/etc/ssh/sshd_config"

sed -i \
  -e 's/^#*Storage=.*/Storage=volatile/' \
  -e 's/^#*RuntimeMaxUse=.*/RuntimeMaxUse=16M/' \
  "$dest/etc/systemd/journald.conf"

install -o root -g root -m644 /dev/stdin "$dest/etc/locale.conf" <<EOF
LANG=$locale
LC_COLLATE=C
LC_MESSAGES=C
EOF

install -o root -g root -m644 /dev/stdin "$dest/etc/systemd/network/10-eth0.network" <<EOF
[Match]
Name=eth0

[Network]
DHCP=ipv4
LLDP=no
LLMNR=no
MulticastDNS=no
DNSSEC=no
EOF

install -o root -g root -m644 /dev/stdin "$dest/root/.bash_profile" <<EOF
. "\$HOME/.bashrc"
EOF

install -o root -g root -m644 /dev/stdin "$dest/root/.bashrc" <<EOF
# if not running interactively, don't do anything
[[ \$- = *i* ]] || return

set -o vi

shopt -s histappend
HISTCONTROL=ignoreboth
HISTIGNORE='ls:ll:pwd:bg:fg:history'
#HISTSIZE=100000
#HISTFILESIZE=10000000

export PS1='\\[\\e[1;31m\\]\\u\\[\\e[00m\\]@\\[\\e[0;31m\\]\\h\\[\\e[1;34m\\]\\w\\[\\e[00m\\]\\\$ '

# directory listing
eval "\$(dircolors -b)"
alias ls='ls --color=auto -F'
alias ll='ls -Ahl'

# some more alias to avoid making mistakes:
alias rm='rm -ri'
alias cp='cp -rid'
alias mv='mv -i'

# editor
export EDITOR='vim'
alias vi='vim'

# pager
export PAGER='less'
export LESS='-FRXS'

# network
alias ip6='ip -6'

# systemd
alias start='systemctl start'
alias stop='systemctl stop'
alias restart='systemctl restart'
alias status='systemctl status'
alias cgls='systemd-cgls'
alias cgtop='systemd-cgtop'

stty -ixon
cd
EOF

install -o root -g root -m700 -d "$dest/root/.ssh"
install -o root -g root -m644 /dev/stdin "$dest/root/.ssh/authorized_keys" <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGkbb5OvfgSMDsP5KEKvGX/LuQ4iclFp6ZJu7mvpHRxD root@qemu
EOF

if [[ -n "$rootdev" ]]; then
  dd if=/dev/zero of="$rootmnt/zero-filler" bs=512M || true
  dd if=/dev/zero of="$rootmnt/zero-filler" bs=512 conv=notrunc oflag=append || true
  rm -f "$rootmnt/zero-filler"
  fstrim -v "$rootmnt"
fi

# vim: set ts=2 sw=2 et:
