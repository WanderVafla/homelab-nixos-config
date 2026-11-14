# Working with the homelab repository

The server configuration lives in `WanderVafla/homelab-nixos-config` (NixOS flake).
The host applies `main` automatically. You change the server only through pull requests.

## Setup

- Work in `/var/lib/hermes/workspace/homelab-nixos-config`.
  If it is missing: `gh repo clone WanderVafla/homelab-nixos-config`.
- `gh` and `git` authenticate with `HOMELAB_REPO_TOKEN` (the `gh` wrapper exports it as `GH_TOKEN`).
  Never print, log or commit it.

## Making a change

1. `git switch main && git pull`, then `git switch -c <short-topic>`.
2. Edit the files. Keep each module to one idea, comments in English.
3. Commit with a clear English message and push the branch.
4. Open a PR: `gh pr create --fill`. Write the PR title and body in English.
5. Wait for CI: `gh pr checks --watch`. CI runs `nix flake check` and a dry-run build.
   You cannot build Nix inside this container, so CI is your only build check.

## Who merges

- **You merge** (`gh pr merge --squash --delete-branch`) only when every changed file is
  under `modules/hermes/` and CI is green. These changes affect only your own container.
- **The owner merges** everything else. Add the label: `gh pr create --fill --label needs-review`.
  This covers any file outside `modules/hermes/`, anything that opens network ports,
  touches secrets, or that you are unsure about.
  Tell the owner in Russian what the PR does and that it needs `sudo homelab-deploy approve` after merge.

## After a merge

- Deploy now instead of waiting up to 5 minutes: `touch /var/lib/homelab-deploy-trigger/request`.
- Read the result in `/var/lib/homelab-deploy/status.json` (`state`, `rev`, `message`):
  - `deployed`: applied and boot default.
  - `awaiting-approval`: protected files changed; the owner must run `sudo homelab-deploy approve`.
  - `failed`: build, invariants or health check failed and the host rolled back. Read `message`,
    fix it in a new PR. The same commit is not retried.
  - `building` / `testing`: wait and check again.

## Rules

- Never push to `main` directly (GitHub blocks it anyway).
- Never edit `secrets/` or try to decrypt anything. Ask the owner to add secrets.
- Never weaken SSH, the firewall, the deployer or the container setup in `modules/base/`.
- Delegate code writing for server configuration to a subagent, then review the diff yourself.
