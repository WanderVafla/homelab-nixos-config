# Telegram approval bot: posts every commit that waits for approval with Approve/Reject buttons,
# approves it when the owner presses Approve, and reports approved deploys and every failed one.
# It also runs the skill watcher (skill-watch.sh, prepended by the Nix module).
#
# Settings (STATE_DIR, DEPLOY_STATE_DIR) are prepended by the Nix module. The environment file
# provides APPROVAL_BOT_TOKEN, APPROVAL_CHAT_ID and APPROVAL_OWNER_ID. Without the two IDs the
# bot runs in setup mode and only answers /chatid.

OFFSET_FILE="$STATE_DIR/offset"
NOTIFIED_FILE="$STATE_DIR/notified-rev"
WATCH_FILE="$STATE_DIR/watch"
REPORTED_FILE="$STATE_DIR/reported-status"
PENDING_FILE="$DEPLOY_STATE_DIR/pending-rev"
STATUS_FILE="$DEPLOY_STATE_DIR/status.json"

APPROVAL_CHAT_ID=${APPROVAL_CHAT_ID:-}
APPROVAL_OWNER_ID=${APPROVAL_OWNER_ID:-}
# Optional topic id of the owner's group: when set, messages go into that topic.
APPROVAL_THREAD_ID=${APPROVAL_THREAD_ID:-}

log() { echo "[approval-bot] $*" >&2; }

read_file() { cat "$1" 2>/dev/null || true; }

# Call a Bot API method with a JSON body. The URL goes through stdin, so the token never
# appears in the process list.
api() { # method json
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$APPROVAL_BOT_TOKEN" "$1" |
    curl --silent --show-error --max-time 60 --config - \
      --header 'Content-Type: application/json' --data-binary "$2"
}

send() { # chat text [reply_markup] [thread_id]
  api sendMessage "$(jq -nc --arg chat "$1" --arg text "$2" --argjson markup "${3:-null}" \
    --argjson thread "${4:-null}" \
    '{chat_id: $chat, text: $text, disable_web_page_preview: true}
     + (if $markup == null then {} else {reply_markup: $markup} end)
     + (if $thread == null then {} else {message_thread_id: $thread} end)')" >/dev/null
}

# Replace a message's text and drop its buttons.
edit() { # chat message_id text
  api editMessageText "$(jq -nc --arg chat "$1" --argjson id "$2" --arg text "$3" \
    '{chat_id: $chat, message_id: $id, text: $text, disable_web_page_preview: true}')" >/dev/null || true
}

answer() { # callback_query_id text
  api answerCallbackQuery "$(jq -nc --arg id "$1" --arg text "$2" \
    '{callback_query_id: $id, text: $text}')" >/dev/null || true
}

configured() { [[ -n $APPROVAL_CHAT_ID && -n $APPROVAL_OWNER_ID ]]; }

# Post the pending commit once, with buttons bound to its full hash.
notify_pending() {
  local rev summary buttons
  rev=$(read_file "$PENDING_FILE")
  if [[ -z $rev || $rev == "$(read_file "$NOTIFIED_FILE")" ]]; then return; fi
  summary=$(homelab-deploy summary 2>&1 | head -c 3500) || return
  buttons=$(jq -nc --arg rev "$rev" \
    '{inline_keyboard: [[{text: "Одобрить", callback_data: ("approve:" + $rev)},
                         {text: "Отклонить", callback_data: ("reject:" + $rev)}]]}')
  if send "$APPROVAL_CHAT_ID" "Ждёт одобрения.
$summary" "$buttons" "$APPROVAL_THREAD_ID"; then
    echo "$rev" >"$NOTIFIED_FILE"
  fi
}

# Report finished deploys once each: every failure, and the result of a deploy you approved.
report_status() {
  local time state rev message
  [[ -f $STATUS_FILE ]] || return 0
  time=$(jq -r .time "$STATUS_FILE")
  if [[ $time == "$(read_file "$REPORTED_FILE")" ]]; then return 0; fi
  state=$(jq -r .state "$STATUS_FILE")
  rev=$(jq -r .rev "$STATUS_FILE")
  message=$(jq -r .message "$STATUS_FILE")
  case $state in
    failed)
      send "$APPROVAL_CHAT_ID" "Деплой ${rev:0:7} не прошёл: $message
Нужен новый коммит с исправлением или: sudo homelab-deploy retry" "$APPROVAL_THREAD_ID" || return 0
      rm -f "$WATCH_FILE"
      ;;
    deployed)
      if [[ -f $WATCH_FILE ]]; then
        send "$APPROVAL_CHAT_ID" "Деплой ${rev:0:7}: deployed
$message" "" "$APPROVAL_THREAD_ID" || return 0
        rm -f "$WATCH_FILE"
      fi
      ;;
    awaiting-approval) ;; # notify_pending posts the buttons
    *) return 0 ;;        # still running: report when it finishes
  esac
  echo "$time" >"$REPORTED_FILE"
}

on_callback() { # callback_query json
  local id from chat message_id data action rev text
  id=$(jq -r .id <<<"$1")
  from=$(jq -r .from.id <<<"$1")
  chat=$(jq -r .message.chat.id <<<"$1")
  message_id=$(jq -r .message.message_id <<<"$1")
  data=$(jq -r '.data // ""' <<<"$1")
  text=$(jq -r '.message.text // ""' <<<"$1")
  if [[ $from != "$APPROVAL_OWNER_ID" || $chat != "$APPROVAL_CHAT_ID" ]]; then
    answer "$id" "Нет доступа"
    log "ignored a button press from user $from in chat $chat"
    return
  fi
  action=${data%%:*}
  rev=${data#*:}
  case $action in
    approve)
      if homelab-deploy approve "$rev" >&2; then
        touch "$WATCH_FILE"
        answer "$id" "Одобрено"
        edit "$chat" "$message_id" "$text

Одобрено, деплой запущен."
      else
        answer "$id" "Этот коммит уже не ждёт одобрения"
        edit "$chat" "$message_id" "$text

Уже не актуально."
      fi
      ;;
    reject)
      answer "$id" "Отклонено"
      edit "$chat" "$message_id" "$text

Отклонено. Следующий коммит в main снова придёт на одобрение."
      ;;
    sk)
      on_skill_button "$id" "$chat" "$message_id" "$text" "$data" || answer "$id" "Ошибка, см. журнал бота"
      ;;
    *) answer "$id" "Неизвестная кнопка" ;;
  esac
}

on_message() { # message json
  local text chat from password thread
  text=$(jq -r '.text // ""' <<<"$1")
  if [[ $text == /chatid* ]]; then
    chat=$(jq -r .chat.id <<<"$1")
    from=$(jq -r .from.id <<<"$1")
    thread=$(jq -r '.message_thread_id // ""' <<<"$1")
    send "$chat" "APPROVAL_CHAT_ID=$chat
APPROVAL_OWNER_ID=$from
APPROVAL_THREAD_ID=$thread" "" "$APPROVAL_THREAD_ID" || true
  fi
  if [[ $text == /grafanapassword* ]]; then
    chat=$(jq -r .chat.id <<<"$1")
    from=$(jq -r .from.id <<<"$1")
    # Only the owner may read the password, and only in the approval chat.
    if [[ $from != "$APPROVAL_OWNER_ID" || $chat != "$APPROVAL_CHAT_ID" ]]; then
      log "ignored /grafanapassword from user $from in chat $chat"
      return
    fi
    password=$(tr -d '[:space:]' </var/lib/grafana-admin-password 2>/dev/null || true)
    if [[ -n $password ]]; then
      send "$chat" "Логин: vladyslav
Пароль: $password" "" "$APPROVAL_THREAD_ID" || true
    else
      send "$chat" "Не смог прочитать /var/lib/grafana-admin-password" "" "$APPROVAL_THREAD_ID" || true
    fi
  fi
}

main() {
  local offset updates update
  offset=$(read_file "$OFFSET_FILE")
  if ! configured; then
    log "setup mode: add the bot to the group and send /chatid"
  fi
  while true; do
    if configured; then
      notify_pending
      report_status
      scan_skills || log "skill watch failed"
    fi
    if ! updates=$(api getUpdates "$(jq -nc --argjson offset "${offset:-0}" \
      '{offset: $offset, timeout: 25, allowed_updates: ["message", "callback_query"]}')"); then
      sleep 10
      continue
    fi
    if [[ $(jq -r .ok <<<"$updates") != true ]]; then
      log "getUpdates failed: $(jq -r '.description // "unknown error"' <<<"$updates")"
      sleep 10
      continue
    fi
    while IFS= read -r update; do
      [[ -n $update ]] || continue
      offset=$(($(jq -r .update_id <<<"$update") + 1))
      echo "$offset" >"$OFFSET_FILE"
      if jq -e .callback_query >/dev/null <<<"$update"; then
        if configured; then on_callback "$(jq -c .callback_query <<<"$update")"; fi
      elif jq -e .message >/dev/null <<<"$update"; then
        on_message "$(jq -c .message <<<"$update")"
      fi
    done < <(jq -c '.result[]' <<<"$updates")
  done
}

main
