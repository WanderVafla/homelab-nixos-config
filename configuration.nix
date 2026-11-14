{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/base
    ./modules/system
  ];

  system.stateVersion = "26.05";
}
