#!/bin/sh
set -o errexit
set -o nounset

IS_VAGRANT_BUILD=${IS_VAGRANT_BUILD:-no}

# TODO: allow selection of device
DEVICE=/dev/$(test -b /dev/vda && echo vda || echo sda)

# TODO: calculate swap-size: round(sqrt(RAM))
SWAP_SIZE=${SWAP_SIZE:-2G}
ROOTFS_SIZE=${ROOTFS_SIZE:-1T}

function customize_configuration {
    # enable ssh
    sed -i s/"# services.openssh.enable"/services.openssh.enable/ /mnt/etc/nixos/configuration.nix

    # remove the last closing curling bracket, so we can more easily add a block of text
    sed -i 's/^}$//' /mnt/etc/nixos/configuration.nix

    cat >> /mnt/etc/nixos/configuration.nix <<EOF
users = {
    mutableUsers = false;

    users = {
        root = {
            initialPassword = "root";
            # hashedPassword = "\$(mkpasswd -m SHA-512)";
            openssh.authorizedKeys.keys = [
                $(generate_authorized_keys)
            ];
        };
    };
};
EOF

    # ZFS configuration
    cat >> /mnt/etc/nixos/configuration.nix <<EOF
boot.supportedFilesystems = [ "zfs" ];
networking.hostId = "$(head -c 8 /etc/machine-id)";
EOF

    # and re-add the closing bracket
    echo "}" >> /mnt/etc/nixos/configuration.nix
}

function setup_vagrant {
    packer_http=$(cat .packer_http)
    curl -f "$packer_http/configuration.nix" > /mnt/etc/nixos/configuration.nix
    curl -f "$packer_http/vagrant.nix" > /mnt/etc/nixos/vagrant.nix
    echo "{}" > /mnt/etc/nixos/vagrant-hostname.nix
    echo "{}" > /mnt/etc/nixos/vagrant-network.nix
}

function generate_authorized_keys {
    if [ -f /etc/ssh/authorized_keys.d/root ]; then
        cat /etc/ssh/authorized_keys.d/root | awk 'NF {print "\"" $0 "\"" }'
    fi

    if [ -f /root/.ssh/authorized_keys ]; then
        cat /root/.ssh/authorized_keys | awk 'NF {print "\"" $0 "\"" }'
    fi
}

function setup_disk {
    UEFI=$(test -d /sys/firmware/efi && echo 1 || echo 0)
    if [ ${UEFI} -eq 1 ]; then
        sfdisk ${DEVICE} <<EOF
            label: gpt

            size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=esp
            size=${SWAP_SIZE}, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name=swap
            size=${ROOTFS_SIZE}, type=6A898CC3-1DD2-11B2-99A6-080020736631, name=rootfs
EOF

        BOOT_DEVICE=/dev/disk/by-partlabel/esp
        SWAP_DEVICE=/dev/disk/by-partlabel/swap
        ROOT_DEVICE=/dev/disk/by-partlabel/rootfs

        BOOT_MKFS=mkfs.vfat
    else
        sfdisk ${DEVICE} <<EOF
            label: dos

            size=512M
            size=${SWAP_SIZE},type=82
            size=${ROOTFS_SIZE}
EOF

        BOOT_DEVICE=${DEVICE}1
        SWAP_DEVICE=${DEVICE}2
        ROOT_DEVICE=${DEVICE}3

        BOOT_MKFS="mkfs.ext4 -FF"
    fi

    # wait for disks/partlabels to be available
    udevadm settle --exit-if-exists ${BOOT_DEVICE}
    udevadm settle --exit-if-exists ${SWAP_DEVICE}
    udevadm settle --exit-if-exists ${ROOT_DEVICE}

    # swap
    mkswap -L swap ${SWAP_DEVICE}
    swapon -L swap

    # TODO: remove -f
    zpool create -O mountpoint=none -O compression=lz4 -R /mnt -f rpool ${ROOT_DEVICE}

    zfs create -o mountpoint=none rpool/ROOT
    zfs create -o mountpoint=legacy rpool/ROOT/nixos

    mount -t zfs rpool/ROOT/nixos /mnt
    for i in home nix tmp var
    do
        mkdir /mnt/${i}
        zfs create -o mountpoint=legacy rpool/${i}
        mount -t zfs rpool/${i} /mnt/${i}
    done

    chmod 1777 /mnt/tmp

    # boot partition
    ${BOOT_MKFS} ${BOOT_DEVICE}
    mkdir /mnt/boot
    mount ${BOOT_DEVICE} /mnt/boot
}

setup_disk

# setup nix configuration
nixos-generate-config --root /mnt
if [ $IS_VAGRANT_BUILD = "yes" ]; then
    setup_vagrant
else
    customize_configuration
    generate_authorized_keys
fi

# start installation
nixos-install --no-root-passwd

if [ $IS_VAGRANT_BUILD = "no" ]; then
    reboot
fi
