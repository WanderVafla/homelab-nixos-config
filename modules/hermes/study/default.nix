# Study tools for the agent: the gcal calendar tool, the moodle-calendar skill and Anki cards.
# The Moodle gateway itself is in the protected layer (modules/base/study).
{ pkgs, ... }:

let
  gcal = pkgs.writers.writePython3Bin "gcal" {
    libraries = with pkgs.python3Packages; [ google-auth requests tzdata ];
    flakeIgnore = [ "E501" ];
    makeWrapperArgs = [ "--set" "GOOGLE_CALENDAR_KEY_FILE" "/run/secrets/google-calendar-key" ];
  } (builtins.readFile ./gcal.py);
in
{
  imports = [ ./anki ];

  services.hermes-agent = {
    extraPackages = [ gcal pkgs.curl ];
    hermesHomeFiles."skills/moodle-calendar/SKILL.md" = ./skills/moodle-calendar/SKILL.md;
  };
}
