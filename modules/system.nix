{ config, lib, pkgs, ... }:

{
  environment.enableAllTerminfo = true;

  powerManagement.cpuFreqGovernor = "performance";
}