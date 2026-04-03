#!/usr/bin/env bash

set -eux

# disable apt prompts
export DEBIAN_FRONTEND=noninteractive

# external variables that must be set
echo vars: $ARCH $BINFMT_ARCH $DEBIAN_VERSION $DOCKER_VERSION $RUNTIME

FILENAME="debian-${DEBIAN_VERSION}-genericcloud-${ARCH}-daily"

SCRIPT_DIR=$(realpath "$(dirname "$(dirname $0)")")
IMG_DIR="$SCRIPT_DIR/dist/img"
CHROOT_DIR=/mnt/colima-img

FILE="$IMG_DIR/$FILENAME"

install_dependencies() (
    echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0"; Acquire::Retries "5"; Dpkg::Use-Pty "0"; Dpkg::Progress-Fancy="0";' > /etc/apt/apt.conf.d/qcow
    apt-get -qq update
    apt-get -qq install -y file libdigest-sha-perl qemu-utils kpartx
)

convert_file() (
    qemu-img convert -p -f qcow2 -O raw $FILE.qcow2 $FILE.raw
)

mount_chroot() {
    LOOP_DEV=$(losetup -Pf --show "$FILE.raw")

    kpartx -avs "$LOOP_DEV"

    LOOP_NAME=$(basename "$LOOP_DEV")
    ROOT_PART="/dev/mapper/${LOOP_NAME}p1"

    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
    mkdir -p "/dev/disk/by-uuid"
    ln -s "/dev/mapper/${LOOP_NAME}p1" "/dev/disk/by-uuid/$ROOT_UUID"

    mkdir -p "$CHROOT_DIR"
    mount "$ROOT_PART" "$CHROOT_DIR"

    chroot_exec mount -t proc proc /proc

    mount --bind /proc "$CHROOT_DIR/proc"
    mount --bind /sys "$CHROOT_DIR/sys"
    mount --bind /dev "$CHROOT_DIR/dev"

    echo 'Dpkg::Use-Pty "0"; Dpkg::Progress-Fancy="0";' > $CHROOT_DIR/etc/apt/apt.conf.d/qcow
}

unmount_chroot() (
    rm $CHROOT_DIR/etc/apt/apt.conf.d/qcow

    umount -l "$CHROOT_DIR/proc"
    umount -l "$CHROOT_DIR/sys"
    umount -l "$CHROOT_DIR/dev"

    umount -l "$CHROOT_DIR"

    kpartx -ds "$LOOP_DEV"
    losetup -d "$LOOP_DEV"
)

chroot_exec() (
    chroot $CHROOT_DIR "$@"
)

install_packages() (
    # necessary

    # internet
    chroot_exec mv /etc/resolv.conf /etc/resolv.conf.bak
    echo 'nameserver 1.1.1.1' >$CHROOT_DIR/etc/resolv.conf

    # minimal
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "0";' > /etc/apt/apt.conf.d/01_nocache
    echo 'APT::Install-Recommends "0"; APT::Install-Suggests "0"; Acquire::Retries "5";' > $CHROOT_DIR/etc/apt/apt.conf.d/minimal
    chroot_exec apt-get -qq purge -y groff-base man-db manpages
    chroot_exec apt-get -qq autoremove -y
    cat >$CHROOT_DIR/etc/dpkg/dpkg.cfg.d/01_nodoc <<"EOF"
path-exclude=/usr/share/locale/*;
path-exclude=/usr/share/man/*;
path-exclude=/usr/share/doc/*;
path-include=/usr/share/doc/*/copyright;
EOF
    pushd $CHROOT_DIR
    rm -rf usr/share/doc/*
    rm -rf usr/share/man/*
    rm -rf usr/share/locale/*
    popd

    # prepare packages
    chroot_exec apt-get -qq update

    # packages common to all runtimes, to prevent from final purging
    chroot_exec apt-get -qq install -y sshfs gnupg dnsmasq
    chroot_exec apt-get -qq install -y htop dnsutils net-tools telnet

    # docker
    if [ "$RUNTIME" == "docker" ]; then
        (
            chroot_exec curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
            chroot_exec sh /tmp/get-docker.sh --version $DOCKER_VERSION
            chroot_exec rm /tmp/get-docker.sh
            chroot_exec apt-mark hold docker-ce docker-ce-cli containerd.io
        )
    fi

    # containerd
    if [ "$RUNTIME" == "containerd" ]; then
        (
            cd /tmp
            tar Cxfz ${CHROOT_DIR}/usr/local /build/dist/containerd/containerd-utils-${ARCH}.tar.gz
            chroot_exec mkdir -p /opt/cni
            chroot_exec mv /usr/local/libexec/cni /opt/cni/bin
        )
    fi

    # incus
    if [ "$RUNTIME" == "incus" ]; then
        (
            chroot_exec sed -i 's/Components: main$/Components: main contrib/' /etc/apt/sources.list.d/debian.sources
            chroot_exec mkdir -p /etc/apt/keyrings/
            chroot_exec curl -fsSL https://pkgs.zabbly.com/key.asc -o /etc/apt/keyrings/zabbly.asc
            chroot_exec sh -c 'cat <<EOF > /etc/apt/sources.list.d/zabbly-incus-stable.sources
Enabled: yes
Types: deb
URIs: https://pkgs.zabbly.com/incus/stable
Suites: $(. /etc/os-release && echo ${VERSION_CODENAME})
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/zabbly.asc

EOF'
            chroot_exec apt-get -qq update
            chroot_exec apt-get -qq install -y incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools
            chroot_exec apt-mark hold incus incus-base incus-client incus-extra incus-ui-canonical zfsutils-linux btrfs-progs lvm2 thin-provisioning-tools
        )
    fi

    chroot_exec apt-get -qq purge -y console-setup-linux dbus-user-session liblocale-gettext-perl parted pciutils pollinate python3-gi snapd ssh-import-id
    chroot_exec apt-get -qq purge -y unattended-upgrades systemd-resolved
    chroot_exec apt-get -qq purge -y apt-listchanges apt-utils
    chroot_exec apt-get -qq purge -y bash-completion
    chroot_exec apt-get -qq purge -y nano
    chroot_exec apt-get -qq purge -y reportbug screen
    chroot_exec apt-get -qq purge -y whiptail
    chroot_exec apt-get -qq purge -y xml-core

    chroot_exec apt-get -qq autoremove -y
    chroot_exec apt-get -qq clean -y
    chroot_exec sh -c "rm -rf /var/lib/apt/lists/* /var/cache/apt/*"

    # binfmt
    (
        cd /tmp
        tar xfz /build/dist/binfmt/binfmt-${ARCH}.tar.gz
        chown root:root binfmt qemu-i386 qemu-${BINFMT_ARCH}
        mv binfmt qemu-i386 qemu-${BINFMT_ARCH} ${CHROOT_DIR}/usr/bin
    )

    # lima compatible boot console
    echo "virtio_console" >> $CHROOT_DIR/etc/initramfs-tools/modules
    chroot_exec update-initramfs -k all -u
    mkdir -p $CHROOT_DIR/etc/default/grub.d
    cat >"$CHROOT_DIR"/etc/default/grub.d/99-lima-console.cfg <<"EOF"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX console=ttyS0 console=hvc0"
EOF
    chroot_exec update-grub

    # enable vsock modules at boot
    cat > ${CHROOT_DIR}/etc/modules-load.d/vsock.conf <<EOF
vsock
virtio_vsock
EOF

    # clean traces
    chroot_exec rm /etc/resolv.conf
    chroot_exec mv /etc/resolv.conf.bak /etc/resolv.conf

    # fill partition with zeros, to recover space during compression
    chroot_exec dd if=/dev/zero of=/root/zero || echo done
    chroot_exec rm -f /root/zero
)

compress_file() (
    qcow_file="${FILE}-${RUNTIME}"
    qemu-img convert -p -f raw -O qcow2 -c $FILE.raw $qcow_file.qcow2
    dir="$(dirname $qcow_file)"
    filename="$(basename $qcow_file)"
    (cd $dir && shasum -a 512 "${filename}.qcow2" >"${filename}.qcow2.sha512sum")
    rm $FILE.raw
)

# perform all actions
install_dependencies
convert_file
mount_chroot
install_packages
unmount_chroot
compress_file
