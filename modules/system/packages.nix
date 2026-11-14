# Base command-line tools available system-wide.
{ pkgs, ... }:

{
  environment.enableAllTerminfo = true;

  environment.systemPackages = with pkgs; [
    git
  ];
}
