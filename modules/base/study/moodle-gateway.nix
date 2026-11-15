# Read-only Moodle gateway, running inside the hermes container under its own user.
# The agent calls http://127.0.0.1:8070 and never reads the token. This file lives in the
# protected layer, so the agent cannot widen the allowlist without the owner's approval.
{ lib, pkgs, ... }:

let
  gatewayUid = 2001; # must match the owner of the moodle-token secret in ./default.nix

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
  users.users.moodle-gateway = {
    isSystemUser = true;
    uid = gatewayUid;
    group = "moodle-gateway";
  };
  users.groups.moodle-gateway.gid = gatewayUid;

  systemd.services.moodle-gateway = {
    description = "Read-only Moodle API gateway for the agent";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      MOODLE_URL = "https://moodle.epsic.ch";
      MOODLE_TOKEN_FILE = "/run/secrets/moodle-token";
      MOODLE_ALLOWED_FUNCTIONS = lib.concatStringsSep " " allowedFunctions;
      PORT = "8070";
    };
    serviceConfig = {
      ExecStart = "${gateway}/bin/moodle-gateway";
      User = "moodle-gateway";
      Group = "moodle-gateway";
      Restart = "always";
      RestartSec = 10;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
