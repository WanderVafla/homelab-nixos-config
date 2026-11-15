# homelab-nixos-config

NixOS flake for `homelab-server`.

- `modules/base/` — lifeline layer: SSH, Tailscale, firewall, watchdog, admin user, deployer, hermes container.
- `modules/system/` — general system settings.
- `modules/hermes/` — Hermes agent settings, evaluated inside the hermes container.
  `modules/hermes/agent-skills/` holds the agent's own skills (Markdown only).
- `modules/base/hermes-policy/` — the agent's instructions (AGENTS.md, SOUL.md, the owner's
  skills), mounted read-only into the container.
- `secrets/` — agenix recipients and encrypted secrets.

## Deploying

`homelab-deploy` on the server applies the newest `main` every 5 minutes, or at once when a file
appears in `/var/lib/homelab-deploy-trigger/`. It checks invariants, activates with `test`, runs a
health check, then promotes the new generation or rolls back.

Any change waits for the owner (Telegram button or `sudo homelab-deploy approve`), except Markdown
files under `modules/hermes/agent-skills/`: Nix in the container config runs as root there and could
read the secrets mounted into the container.
