{ config, lib, pkgs, ... }:

let
  kickstart = pkgs.writeScriptBin "kickstart.sh" (builtins.readFile ./kickstart.sh);
in
{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>

    # Provide an initial copy of the NixOS channel so that the user
    # doesn't need to run "nix-channel --update" first.
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
  ];

  environment.systemPackages = [
    kickstart
  ];

  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  users.extraUsers.root.openssh.authorizedKeys.keyFiles = [ (builtins.fetchurl https://github.com/zauberpony.keys) ];

  boot.loader.grub.memtest86.enable = lib.mkForce false;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Additional packages to include in the store.
  system.extraDependencies = [ ];
}
