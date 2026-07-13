{ config, lib, pkgs, ... }:

{
  users.users.WanderVafla = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
  };

  users.users.github_deploy = {
    isNormalUser = true;
    extraGroups = [];
    shell = "${pkgs.shadow}/sbin/nologin";
    description = "Deploy automation user";
  };

  security.sudo.extraRules = [
    {
      users = [ "github_deploy" ];
      command = [
        {
          command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
          options = [ "NOPASSWD" "SETENV" ];
        }
      ];
    }
  ];
}