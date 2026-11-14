# Hermes agent settings. Evaluated inside the hermes container only, so changes here cannot affect the host.
# This is the one directory the agent may change without owner approval.
{ config, inputs, pkgs, ... }:

{
  imports = [
    inputs.hermes-agent.nixosModules.default
    ./git.nix
  ];

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
    addToSystemPackages = true;

    # Provided by the host (modules/base/hermes-container.nix).
    environmentFiles = [ "/run/secrets/hermes-env" ];

    settings = {
      # Main model for conversation and planning. OPENROUTER_API_KEY comes from hermes-env.
      model = {
        provider = "openrouter";
        default = "anthropic/claude-sonnet-5.5";
      };

      # Cheap model for side tasks instead of the main model.
      auxiliary = pkgs.lib.genAttrs [ "compression" "title_generation" "vision" "approval" ] (_: {
        provider = "openrouter";
        model = "anthropic/claude-haiku-5.5";
      });

      # Subagents (delegate_task) write server configuration code; see SOUL.md.
      delegation = {
        provider = "openrouter";
        model = "deepseek/deepseek-v4.1-flash";
      };

      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };

      # Terminal commands get no secrets except the repository token. Hermes never forwards
      # GH_TOKEN or GITHUB_TOKEN (its own credentials), so the token uses a custom name.
      terminal.env_passthrough = [ "HOMELAB_REPO_TOKEN" ];
    };

    # AGENTS.md tells the agent how to work with the homelab repository.
    workingDirectory = "/var/lib/hermes/workspace";
    documents."AGENTS.md" = ./AGENTS.md;

    hermesHomeFiles."SOUL.md" = ./SOUL.md;

    extraPackages = with pkgs; [
      config.homelab.gh
      git
      jq
      ripgrep
    ];
  };
}
