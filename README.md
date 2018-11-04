Nixos kickstart script
======================

Script to kickstart nixos installation with fixed disk-setup.

## Install-script features

- assumes nixos should be installed to /dev/sda
- completely wipes /dev/sda
- assumes UEFI system
- uses 2GB swap
- uses btrfs with subvolumes for all filesystems (/, /home, /nix, /tmp, /var)
- sets password "root" for "root"

## Installation

Run in nixos-install-live system with:

```
curl -L nixrc.athmer.org | sh
```

Final step of a successfull installation is to reboot.


## Build Custom ISO

```
nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=iso.nix
```

## Vagrant Box

```
nix-shell -p packer --run "packer build nixos-x86_64.json"
```