{ config, lib, pkgs, ... }:

{
  environment.enableAllTerminfo = true;

  environment.systemPackages = with pkgs; [
    git
    vim 
    tmux
  ];
  
  powerManagement.cpuFreqGovernor = "performance";

  environment.etc."gitconfig".text = ''
    [safe]
      directory = /etc/nixos
  '';
}