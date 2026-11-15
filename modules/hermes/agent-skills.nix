# Installs the agent's own skills (agent-skills/<name>/*.md) into HERMES_HOME/skills/<name>/.
# Only Markdown is installed: those files are the only ones the agent may merge by itself.
{ lib, ... }:

let
  dir = ./agent-skills;
  # The owner's skills, mounted read-only by the host (modules/base/hermes-policy).
  protectedSkillNames = lib.attrNames (builtins.readDir ../base/hermes-policy/skills);
  folders = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));

  markdownFiles = name: lib.attrNames (lib.filterAttrs
    (file: type: type == "regular" && lib.hasSuffix ".md" file)
    (builtins.readDir (dir + "/${name}")));

  skillFiles = name: map (file: {
    name = "skills/${name}/${file}";
    value = dir + "/${name}/${file}";
  }) (markdownFiles name);

  clashes = lib.intersectLists folders protectedSkillNames;
in
{
  assertions = [{
    assertion = clashes == [ ];
    message = "agent-skills must not reuse the owner's skill names: ${lib.concatStringsSep ", " clashes}";
  }];

  services.hermes-agent.hermesHomeFiles = lib.listToAttrs (lib.concatMap skillFiles folders);
}
