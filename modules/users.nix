{ config, lib, pkgs, ... }:

{
  users.users.WanderVafla = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
  };

  # modules/users.nix
  users.users.github_deploy = {
    isNormalUser = true;
    extraGroups = [];
    shell = pkgs.bashInteractive;
    description = "Deploy automation user";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQsLpYe6NSaWAQ5mRiHR9sQh87sKhRB8lGDPROOPFXG GitHub CI/CD"
    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "github_deploy" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/nixos-rebuild";
          options = [ "NOPASSWD" "SETENV" ];
        }
      ];
    }
  ];
}