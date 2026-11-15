# Agent skills

Hermes's own skills, one folder per skill: `<name>/SKILL.md`, plus other `.md` files if needed.
Markdown files here are the only files the agent may merge without the owner's approval.
`../agent-skills.nix` installs every `.md` file of every folder into `~/.hermes/skills/<name>/`.

Names must not match the owner's skills in `modules/base/hermes-policy/skills/`.
Any other file type here is ignored by the install and counts as protected.
