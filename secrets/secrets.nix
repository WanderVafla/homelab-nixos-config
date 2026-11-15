# Recipients for agenix secrets. Every secret is encrypted to the host key
# (to decrypt at activation) and the owner's key (to edit and to recover).
let
  host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALFIMKfIWwunIeRa4hZAPfT0T10pj8hi2esA4fyQVFk root@homelab-server";
  owner = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGO3Ob1rxJ7nUEHA73izFtCdUSZcViRVnhLq7lioyzAb procenkovladik1@gmail.com";
  all = [ host owner ];
in
{
  # Environment for the Hermes agent: TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS, model API key,
  # HOMELAB_REPO_TOKEN, GOOGLE_CALENDAR_ID.
  "hermes-env.age".publicKeys = all;
  # Host-only approval bot: APPROVAL_BOT_TOKEN, APPROVAL_CHAT_ID, APPROVAL_OWNER_ID.
  # Never mount it into the hermes container.
  "approval-bot.age".publicKeys = all;
  # Moodle mobile web service token (the bare token). Read only by the Moodle gateway user.
  "moodle-token.age".publicKeys = all;
  # Google service account JSON key for the study calendar. Readable by the agent.
  "google-calendar-key.age".publicKeys = all;
}
