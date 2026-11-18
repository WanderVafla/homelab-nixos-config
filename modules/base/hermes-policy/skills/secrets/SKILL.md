---
name: secrets
description: "Get a secret (API key, token, service password) from the owner with request_secret and wire it into the server with agenix, without ever seeing the value."
version: 1.0.0
metadata:
  hermes:
    tags: [Secrets, agenix, Security]
---

# Secrets from the owner → agenix

Use this whenever a task needs a secret value: an API key, a token, the password of a service you
are setting up. You never see the value, and you must not try to.

## Hard rules

- **Never ask for a secret in plain chat**, in Telegram or anywhere else, and never accept one that
  the owner pastes into a normal message. If the owner does paste one, tell them in Russian to
  revoke it, because it went through the model.
- **Use only `request_secret(name, purpose)`.** It works only in the owner's Telegram chat. In the
  desktop widget it fails: ask the owner to continue the task in Telegram.
- **Never request** the owner's sudo password, SSH keys, GitHub account password or 2FA codes,
  bank or school account passwords. Only secrets for services on this server.
- **Never try to decrypt** a `.age` file, read `/run/agenix`, or print a secret's value.
- One request at a time. If the owner cancels (`/cancel`) or the request times out, ask before
  trying again.

## Steps

1. Pick a short name in lowercase with dashes (`openai-key`, `paperless-admin-password`) and a
   one-sentence purpose in Russian that says where the secret will be used.
2. Call `request_secret(name, purpose)`. It waits up to 10 minutes and returns `path` of an
   age-encrypted file in `/var/lib/hermes/secret-inbox/`.
3. In the repository (see AGENTS.md), on a new branch:
   1. Copy the file to `secrets/<name>.age`.
   2. Add `"<name>.age".publicKeys = all;` to `secrets/secrets.nix`, with a comment that says
      what the secret is and who reads it.
   3. Declare `age.secrets.<name>` in the module that uses it, with the narrowest `owner` and
      `mode` (`0400`). Prefer a host service (like `modules/base/study/moodle-gateway.nix`) over
      mounting the secret into your container.
4. Open the PR with `--label needs-review`. Tell the owner in Russian where the secret goes: to
   a host service, or into your container (and why that is needed).
5. Never put the value, or anything derived from it, into the PR, a log, a commit message or
   your memory. The file name and purpose are fine.
