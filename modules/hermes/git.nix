# Git setup for the agent: identity, GitHub auth through gh, read access to the deployer's clone.
{ lib, pkgs, config, ... }:

{
  # gh that authenticates with HOMELAB_REPO_TOKEN (fine-grained, this repository only).
  options.homelab.gh = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = pkgs.writeShellScriptBin "gh" ''
      export GH_TOKEN="''${HOMELAB_REPO_TOKEN:-}"
      exec ${pkgs.gh}/bin/gh "$@"
    '';
  };

  config.programs.git = {
    enable = true;
    config = {
      user.name = "Hermes (homelab agent)";
      user.email = "hermes@homelab-server";
      init.defaultBranch = "main";
      # The gh wrapper answers git's credential requests with HOMELAB_REPO_TOKEN.
      credential."https://github.com".helper = "!${config.homelab.gh}/bin/gh auth git-credential";
      # The deployer's clone is owned by root on the host and mounted read-only.
      safe.directory = "/var/lib/homelab-deploy/repo";
    };
  };
}
