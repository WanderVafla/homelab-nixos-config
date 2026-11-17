# Hermes agent settings, evaluated inside the hermes container. Protected like the rest of the
# repository: Nix here runs as root in the container. The agent may merge by itself only Markdown
# in ./agent-skills; its instructions (AGENTS.md, SOUL.md, the owner's skills) are mounted
# read-only by the host from modules/base/hermes-policy.
{ config, inputs, pkgs, ... }:

{
  imports = [
    inputs.hermes-agent.nixosModules.default
    ./git.nix
    ./agent-skills.nix
    ./study
  ];

  services.hermes-agent = {
    enable = true;
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
    addToSystemPackages = true;

    # Provided by the host (modules/base/hermes-container.nix).
    environmentFiles = [ "/run/secrets/hermes-env" ];

    settings = {
      # Main model for conversation and planning. OPENROUTER_API_KEY comes from hermes-env.
      # The main model is z-ai/glm-5.3-flash on OpenRouter; the owner can switch one session
      # with `/model <id>` (session-scoped by default).
      model = {
        provider = "openrouter";
        default = "z-ai/glm-5.3-flash";
      };

      # Cheap model for side tasks instead of the main model.
      auxiliary = pkgs.lib.genAttrs [ "compression" "title_generation" "vision" "approval" ] (_: {
        provider = "openrouter";
        model = "z-ai/glm-5.3-flash";
      });

      # Subagents (delegate_task) write server configuration code; see SOUL.md.
      delegation = {
        provider = "openrouter";
        model = "z-ai/glm-5.3-flash";
      };

      # Cron schedules and the time in the prompt follow the owner's clock; the host runs in UTC.
      timezone = "Europe/Zurich";

      # Every enabled tool's schema is sent with every model call. These are unused on a headless
      # server (no desktop, no image or voice replies) and the browser can post data anywhere.
      agent.disabled_toolsets = [ "browser" "computer_use" "image_gen" "tts" "connections" ];

      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };

      # Terminal commands get no secrets except the repository token and the study calendar id.
      # Hermes never forwards GH_TOKEN or GITHUB_TOKEN (its own credentials), so the token uses
      # a custom name.
      terminal.env_passthrough = [ "HOMELAB_REPO_TOKEN" "GOOGLE_CALENDAR_ID" ];
    };

    # AGENTS.md is mounted here by the host (modules/base/hermes-policy).
    workingDirectory = "/var/lib/hermes/workspace";

    # CLI tools for data processing, parsing and search.
    extraPackages = with pkgs; [
      config.homelab.gh
      bat
      fd
      fzf
      git
      jq
      python3
      ripgrep
      sqlite
      unzip
      yq
    ];
  };
}
