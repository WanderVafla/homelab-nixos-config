# Hermes agent settings. Evaluated inside the hermes container only, so changes here cannot affect the host.
# This is the one directory the agent may change without owner approval.
{ inputs, pkgs, ... }:

{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
    addToSystemPackages = true;

    settings = {
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
    };

    hermesHomeFiles."SOUL.md" = ./SOUL.md;

    extraPackages = with pkgs; [
      git
      jq
    ];
  };
}
