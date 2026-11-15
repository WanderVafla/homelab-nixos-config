# Study tools for the agent: the gcal calendar tool and Anki cards.
# The Moodle gateway runs on the host (modules/base/study), at http://10.231.0.1:8070; the skills
# that use these tools are in modules/base/hermes-policy/skills.
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

  services.hermes-agent.extraPackages = [ gcal pkgs.curl ];
}
