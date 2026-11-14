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
  Tell the owner in Russian what the PR does and that it needs approval after merge.
- After such a merge the host's approval bot posts Approve/Reject buttons in Telegram, or the owner
  runs `sudo homelab-deploy approve`. You cannot approve, and never try to.

## After a merge

- A deploy that changes anything under `modules/hermes/` restarts your container. Your current
  session ends in the middle of the task, so prepare before you trigger it:
  1. Schedule a one-shot `cronjob` about 6 minutes from now, delivered to this chat (`origin`),
     with `workdir` set to the repository. Its prompt: read `/var/lib/homelab-deploy/status.json`,
     report the result to the owner in Russian; if `state` is `building` or `testing`,
     schedule another one-shot check in 3 minutes instead.
  2. Tell the owner in Russian that you are restarting now and will report the result.
  Cron jobs survive the restart; anything running in your session does not.
- Deploy now instead of waiting up to 5 minutes: `touch /var/lib/homelab-deploy-trigger/request`.
- Read the result in `/var/lib/homelab-deploy/status.json` (`state`, `rev`, `message`):
  - `deployed`: applied and boot default.
  - `awaiting-approval`: protected files changed; the owner must approve (Telegram button or sudo).
  - `failed`: build, invariants or health check failed and the host rolled back. Read `message`,
    fix it in a new PR. The same commit is not retried.
  - `building` / `testing`: wait and check again.

## Rules

- Never push to `main` directly (GitHub blocks it anyway).
- Never edit `secrets/` or try to decrypt anything. Ask the owner to add secrets.
- Never weaken SSH, the firewall, the deployer or the container setup in `modules/base/`.
- Delegate code writing for server configuration to a subagent, then review the diff yourself.
