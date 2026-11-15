# Skill watcher for the approval bot: every few minutes it compares the agent's skills with the
# last version the owner kept, and posts each added, changed or removed skill with two buttons:
# keep it, or roll it back to the kept version. The first scan only records the current state.
#
# Skipped: the owner's skills (mounted read-only) and bundled skills identical to the Hermes
# package. Everything inside the container is touched as the agent's uid, never as root, so a
# symlink planted there cannot make the bot read or write host files as root.
#
# Settings (SKILLS_DIR, BUNDLED_SKILLS, PROTECTED_SKILLS, HERMES_UID) are prepended by the Nix module.
# State in $STATE_DIR/skills: known ("<key> <hash> <path>" per kept skill), snapshots/<key>.tar
# (the kept version), reported/<key> ("<hash> <path>" of the change already posted).

SKILL_STATE="$STATE_DIR/skills"
KNOWN_FILE="$SKILL_STATE/known"
SKILL_SCAN_INTERVAL=300
last_skill_scan=-$SKILL_SCAN_INTERVAL

as_agent() { setpriv --reuid="$HERMES_UID" --regid="$HERMES_UID" --clear-groups -- "$@"; }

skill_key() { printf '%s' "$1" | sha256sum | cut -c1-16; }

# Deterministic hash of a skill folder (names, modes, contents).
skill_hash() { # path
  as_agent tar -C "$SKILLS_DIR" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    -cf - -- "$1" 2>/dev/null | sha256sum | cut -d' ' -f1
}

known_hash() { # key
  awk -v key="$1" '$1 == key { print $2 }' "$KNOWN_FILE" 2>/dev/null
}

# True if the watcher tracks this skill folder: it exists, is not hidden, not the owner's,
# and not a bundled skill identical to the Hermes package.
tracked() { # path
  [[ $1 == .* || $1 == */.* ]] && return 1
  [[ " $PROTECTED_SKILLS " == *" ${1%%/*} "* ]] && return 1
  as_agent test -f "$SKILLS_DIR/$1/SKILL.md" || return 1
  if [[ -f $BUNDLED_SKILLS/$1/SKILL.md ]] &&
    as_agent cat -- "$SKILLS_DIR/$1/SKILL.md" | cmp -s - "$BUNDLED_SKILLS/$1/SKILL.md"; then
    return 1
  fi
  return 0
}

# Skill folders (relative paths) that the watcher tracks.
list_skills() {
  local file
  while IFS= read -r file; do
    if tracked "${file%/SKILL.md}"; then printf '%s\n' "${file%/SKILL.md}"; fi
  done < <(as_agent find "$SKILLS_DIR" -mindepth 2 -maxdepth 3 -type f -name SKILL.md -printf '%P\n' | sort)
}

# Record the current version of a skill as kept (or forget it if it is no longer tracked).
keep_skill() { # path
  local key hash
  key=$(skill_key "$1")
  awk -v key="$key" '$1 != key' "$KNOWN_FILE" 2>/dev/null >"$KNOWN_FILE.tmp" || true
  if tracked "$1"; then
    hash=$(skill_hash "$1")
    as_agent tar -C "$SKILLS_DIR" -cf - -- "$1" >"$SKILL_STATE/snapshots/$key.tar"
    printf '%s %s %s\n' "$key" "$hash" "$1" >>"$KNOWN_FILE.tmp"
  else
    rm -f "$SKILL_STATE/snapshots/$key.tar"
  fi
  mv "$KNOWN_FILE.tmp" "$KNOWN_FILE"
  rm -f "$SKILL_STATE/reported/$key"
}

# Put back the kept version: the snapshot, else the bundled original, else remove the skill.
revert_skill() { # path
  local key snapshot
  key=$(skill_key "$1")
  snapshot="$SKILL_STATE/snapshots/$key.tar"
  as_agent rm -rf -- "${SKILLS_DIR:?}/$1"
  if [[ -f $snapshot ]]; then
    as_agent tar -C "$SKILLS_DIR" -xf - <"$snapshot"
  elif [[ -d $BUNDLED_SKILLS/$1 ]]; then
    as_agent mkdir -p -- "$SKILLS_DIR/$1"
    as_agent cp -r -- "$BUNDLED_SKILLS/$1/." "$SKILLS_DIR/$1/"
    as_agent chmod -R u+w -- "$SKILLS_DIR/$1"
  fi
  keep_skill "$1"
}

report_skill() { # path hash
  local key text description buttons
  key=$(skill_key "$1")
  if [[ $(read_file "$SKILL_STATE/reported/$key") == "$2 $1" ]]; then return; fi
  if [[ $2 == - ]]; then
    text="🗑️ Навык Hermes удалён: $1"
  elif [[ -n $(known_hash "$key") ]]; then
    text="✏️ Hermes изменил навык: $1"
  else
    text="🧠 Hermes добавил навык: $1"
  fi
  if [[ $2 != - ]]; then
    description=$(as_agent grep -m1 '^description:' -- "$SKILLS_DIR/$1/SKILL.md" 2>/dev/null | head -c 300)
    text+=$'\n'"${description:-без описания}"
  fi
  buttons=$(jq -nc --arg ok "sk:ok:$key:${2:0:8}" --arg rv "sk:rv:$key:${2:0:8}" \
    '{inline_keyboard: [[{text: "👍 Оставить", callback_data: $ok},
                         {text: "↩️ Откатить", callback_data: $rv}]]}')
  if send "$APPROVAL_CHAT_ID" "$text" "$buttons"; then
    printf '%s %s' "$2" "$1" >"$SKILL_STATE/reported/$key"
  fi
}

scan_skills() {
  local path key hash first
  local -A current=()
  ((SECONDS - last_skill_scan >= SKILL_SCAN_INTERVAL)) || return 0
  last_skill_scan=$SECONDS
  if [[ $(realpath -e "$SKILLS_DIR" 2>/dev/null) != "$SKILLS_DIR" ]]; then
    log "skills directory is missing or redirected; skill watch skipped"
    return 0
  fi
  mkdir -p "$SKILL_STATE/snapshots" "$SKILL_STATE/reported"
  [[ -f $KNOWN_FILE ]] || first=1
  while IFS= read -r path; do
    current[$path]=$(skill_hash "$path")
  done < <(list_skills)
  if [[ -n ${first:-} ]]; then
    : >"$KNOWN_FILE"
    for path in "${!current[@]}"; do keep_skill "$path"; done
    log "skill watch: recorded ${#current[@]} skills"
    return 0
  fi
  for path in "${!current[@]}"; do
    key=$(skill_key "$path")
    if [[ ${current[$path]} != "$(known_hash "$key")" ]]; then report_skill "$path" "${current[$path]}"; fi
  done
  while read -r key hash path; do
    if [[ -n $path && -z ${current[$path]+set} ]]; then report_skill "$path" -; fi
  done <"$KNOWN_FILE"
}

# Button "sk:<ok|rv>:<key>:<hash prefix>". Acts only if the skill is still in the reported state.
on_skill_button() { # callback_id chat message_id text data
  local action key prefix reported hash path
  IFS=: read -r _ action key prefix <<<"$5"
  reported=$(read_file "$SKILL_STATE/reported/$key")
  hash=${reported%% *}
  path=${reported#* }
  if [[ -z $reported || ${hash:0:8} != "$prefix" ]]; then
    answer "$1" "Уже не актуально"
    edit "$2" "$3" "$4

Уже не актуально: навык изменился ещё раз или решение уже принято."
    return
  fi
  case $action in
    ok)
      keep_skill "$path"
      answer "$1" "Оставлено"
      edit "$2" "$3" "$4

👍 Оставлено."
      ;;
    rv)
      revert_skill "$path"
      answer "$1" "Откачено"
      edit "$2" "$3" "$4

↩️ Откачено к прошлой версии."
      ;;
    *) answer "$1" "Неизвестная кнопка" ;;
  esac
}
