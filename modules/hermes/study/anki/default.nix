# anki-epsic: the agent adds EPSIC flashcards to the owner's Anki collection and syncs it with
# the host's Anki sync server (modules/services/anki-sync-server.nix).
{ pkgs, ... }:

let
  python = pkgs.python3;
  collectionDir = "/var/lib/hermes/anki";

  anki-epsic = pkgs.writers.writePython3Bin "anki-epsic" {
    flakeIgnore = [ "E501" "W503" ];
    makeWrapperArgs = [
      "--prefix" "PYTHONPATH" ":" "${pkgs.anki.lib}/${python.sitePackages}"
      "--set" "ANKI_COLLECTION" "${collectionDir}/collection.anki2"
      "--set" "ANKI_SYNC_URL" "http://10.231.0.1:27701/"
      "--set" "ANKI_SYNC_USER" "vladyslav"
      "--set" "ANKI_SYNC_PASSWORD_FILE" "/run/secrets/anki-sync-password"
      "--set" "ANKI_EPSIC_TEMPLATES" "${./templates}"
    ];
  } (builtins.readFile ./anki_epsic.py);
in
{
  services.hermes-agent = {
    extraPackages = [ anki-epsic pkgs.poppler-utils ];
    hermesHomeFiles."skills/epsic-cards/SKILL.md" = ./skills/epsic-cards/SKILL.md;
  };

  systemd.tmpfiles.rules = [ "d ${collectionDir} 0700 hermes hermes -" ];
}
