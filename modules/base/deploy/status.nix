# homelab-deploy-status: read-only deploy status as JSON for the owner's desktop widget,
# which runs it over SSH. It can only read; approving still needs sudo homelab-deploy approve.
{ pkgs, ... }:

let
  homelab-deploy-status = pkgs.writeShellApplication {
    name = "homelab-deploy-status";
    runtimeInputs = with pkgs; [ coreutils git jq ];
    text = ''
      # Same values as homelab-deploy in ./default.nix and ./homelab-deploy.sh.
      STATE_DIR="/var/lib/homelab-deploy"
      REMOTE="https://github.com/WanderVafla/homelab-nixos-config.git"
      AGENT_SKILLS_DIR=modules/hermes/agent-skills
    '' + builtins.readFile ./deploy-status.sh;
  };
in
{
  environment.systemPackages = [ homelab-deploy-status ];
}
