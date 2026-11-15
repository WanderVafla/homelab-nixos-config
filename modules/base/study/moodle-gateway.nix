# Read-only Moodle gateway, running on the host. The token never enters the hermes container:
# the agent calls the gateway over its veth link (http://<hostAddress>:8070), and nothing the
# agent can change (modules/hermes) is able to read the token or widen the allowlist.
{ config, lib, pkgs, ... }:

let
  port = 8070;

  gateway = pkgs.writers.writePython3Bin "moodle-gateway" { flakeIgnore = [ "E501" ]; }
    (builtins.readFile ./moodle_gateway.py);

  # Read-only functions only. Never add functions that submit, post, send or mark as viewed.
  allowedFunctions = [
    "core_webservice_get_site_info"
    "core_enrol_get_users_courses"
    "core_course_get_contents"
    "core_course_get_courses_by_field"
    "core_course_get_updates_since"
    "core_calendar_get_action_events_by_timesort"
    "core_calendar_get_calendar_upcoming_view"
    "core_calendar_get_calendar_events"
    "mod_assign_get_assignments"
    "mod_assign_get_submission_status"
    "mod_quiz_get_quizzes_by_courses"
    "mod_resource_get_resources_by_courses"
    "mod_page_get_pages_by_courses"
    "mod_folder_get_folders_by_courses"
    "mod_url_get_urls_by_courses"
    "mod_forum_get_forums_by_courses"
    "mod_forum_get_forum_discussions"
    "mod_forum_get_discussion_posts"
    "gradereport_user_get_grade_items"
  ];
in
{
  # Root-only on the host; systemd hands a copy to the gateway as a credential.
  age.secrets.moodle-token = {
    file = ../../../secrets/moodle-token.age;
    mode = "0400";
  };

  systemd.services.moodle-gateway = {
    description = "Read-only Moodle API gateway for the agent";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    restartTriggers = [ config.age.secrets.moodle-token.file ];
    environment = {
      MOODLE_URL = "https://moodle.epsic.ch";
      MOODLE_ALLOWED_FUNCTIONS = lib.concatStringsSep " " allowedFunctions;
      HOST = config.containers.hermes.hostAddress;
      PORT = toString port;
    };
    serviceConfig = {
      ExecStart = "${gateway}/bin/moodle-gateway";
      LoadCredential = "moodle-token:${config.age.secrets.moodle-token.path}";
      DynamicUser = true;
      Restart = "always";
      RestartSec = 10;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      CapabilityBoundingSet = "";
      SystemCallFilter = [ "@system-service" ];
    };
  };

  # Reachable from the hermes container only: the LAN firewall keeps the port closed, and the
  # gateway listens on the veth address, not on the tailnet.
  networking.firewall.interfaces."ve-hermes".allowedTCPPorts = [ port ];
}
