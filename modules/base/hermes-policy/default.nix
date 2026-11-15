# The agent's instructions: AGENTS.md, SOUL.md and the owner's skills. The host mounts them into
# the hermes container read-only, so the agent can change them neither at runtime (skill_manage,
# plain file writes) nor through the container config. Changes go through a protected PR.
{ lib, ... }:

let
  stateDir = "/var/lib/hermes"; # services.hermes-agent.stateDir inside the container
  hermesHome = "${stateDir}/.hermes";

  readOnly = hostPath: { inherit hostPath; isReadOnly = true; };

  skillMounts = lib.mapAttrs'
    (name: _: lib.nameValuePair "${hermesHome}/skills/${name}" (readOnly "${./skills/${name}}"))
    (builtins.readDir ./skills);
in
{
  containers.hermes.bindMounts = {
    "${stateDir}/workspace/AGENTS.md" = readOnly "${./AGENTS.md}";
    "${hermesHome}/SOUL.md" = readOnly "${./SOUL.md}";
  } // skillMounts;
}
