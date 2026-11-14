# Git setup for the agent: identity, GitHub auth through gh, read access to the deployer's clone.
{ pkgs, ... }:

{
  programs.git = {
    enable = true;
    config = {
      user.name = "Hermes (homelab agent)";
      user.email = "hermes@homelab-server";
      init.defaultBranch = "main";
      # gh reads GH_TOKEN from the environment and answers git's credential requests.
      credential."https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      # The deployer's clone is owned by root on the host and mounted read-only.
      safe.directory = "/var/lib/homelab-deploy/repo";
    };
  };
}
