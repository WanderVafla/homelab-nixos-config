# Desktop chat bridge to the Hermes API server. The laptop runs it over SSH
# (`ssh homelab hermes-chat ...`), so the SSH login is the authorization and
# API_SERVER_KEY never leaves the server.
#
# Set by the Nix wrapper: API_URL (the API inside the hermes container) and
# KEY_FILE (env file with the API_SERVER_KEY= line, readable by the owner only).
#
# Commands:
#   new                         create a session, print its id
#   send <session-id>           message on stdin; print stream events
#   messages <session-id>       print the session history as JSON
#   approve <run-id> <choice>   answer an approval request: once, session or deny
#
# `send` prints one event per line: "<event name><TAB><JSON payload>".

usage() {
  sed -n 's/^#   //p' "$0" >&2
  exit 2
}

# Ids are pasted into a remote shell command line by ssh, so allow only safe characters.
check_id() {
  if [[ ! "$1" =~ ^[A-Za-z0-9_-]{1,128}$ ]]; then
    echo "hermes-chat: invalid id: $1" >&2
    exit 2
  fi
}

# Passes the key in a header file, never on the command line where `ps` would show it.
api() {
  local key
  key=$(sed -n 's/^API_SERVER_KEY=//p' "$KEY_FILE")
  curl --silent --show-error --fail-with-body \
    -H @<(printf 'Authorization: Bearer %s\n' "$key") \
    -H 'Content-Type: application/json' \
    "$@"
}

# Joins the SSE "event:" and "data:" lines of each frame into one tab-separated line.
sse_to_lines() {
  awk '
    /^event: / { event = substr($0, 8); next }
    /^data: /  { print (event == "" ? "message" : event) "\t" substr($0, 7); fflush(); event = ""; next }
  '
}

cmd="${1:-}"
case "$cmd" in
  new)
    [ $# -eq 1 ] || usage
    api -X POST -d '{}' "$API_URL/api/sessions" | jq -r '.session.id'
    ;;
  send)
    [ $# -eq 2 ] || usage
    check_id "$2"
    jq -Rs '{message: .}' |
      api --no-buffer -X POST -H 'Accept: text/event-stream' -d @- \
        "$API_URL/api/sessions/$2/chat/stream" |
      sse_to_lines
    ;;
  messages)
    [ $# -eq 2 ] || usage
    check_id "$2"
    api "$API_URL/api/sessions/$2/messages"
    ;;
  approve)
    [ $# -eq 3 ] || usage
    check_id "$2"
    case "$3" in
      once | session | deny) ;;
      *) usage ;;
    esac
    jq -n --arg choice "$3" '{choice: $choice}' |
      api -X POST -d @- "$API_URL/v1/runs/$2/approval"
    ;;
  *)
    usage
    ;;
esac
