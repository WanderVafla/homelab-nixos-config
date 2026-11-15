{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/base
    ./modules/system
    ./modules/services
  ];

  system.stateVersion = "26.05";
}
