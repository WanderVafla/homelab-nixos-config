# Recipients for agenix secrets. Every secret is encrypted to the host key
# (to decrypt at activation) and the owner's key (to edit and to recover).
let
  host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALFIMKfIWwunIeRa4hZAPfT0T10pj8hi2esA4fyQVFk root@homelab-server";
  owner = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGO3Ob1rxJ7nUEHA73izFtCdUSZcViRVnhLq7lioyzAb procenkovladik1@gmail.com";
  all = [ host owner ];
in
{
  # No secrets yet. Example:
  # "telegram-bot.age".publicKeys = all;
}
