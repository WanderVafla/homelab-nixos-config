# Pull-based NixOS deployer: fetch -> approval gate -> build -> invariants -> test -> health check
# -> promote to boot default, or roll back to the previous system.
#
# Settings (REMOTE, BRANCH, HOST, ADMIN_USER, STATE_DIR, TRIGGER_DIR, HEALTH_TIMEOUT, HEALTH_UNITS)
# are prepended by the Nix module.

REPO="$STATE_DIR/repo"
STATUS_FILE="$STATE_DIR/status.json"
DEPLOYED_FILE="$STATE_DIR/deployed-rev"
FAILED_FILE="$STATE_DIR/failed-rev"
PENDING_FILE="$STATE_DIR/pending-rev"
APPROVED_FILE="$STATE_DIR/approved-protected-hash"
PROFILE=/nix/var/nix/profiles/system
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904

# Everything in the repository needs the owner's approval on the server, except these paths.
# modules/hermes is evaluated inside the hermes container only, so it cannot affect the host.
AGENT_PATHS=(modules/hermes)

log() { echo "[homelab-deploy] $*" >&2; }

read_file() { cat "$1" 2>/dev/null || true; }

write_status() { # state rev message
  jq -n --arg state "$1" --arg rev "$2" --arg message "$3" --arg time "$(date -Is)" \
    '{state: $state, rev: $rev, message: $message, time: $time}' >"$STATUS_FILE.tmp"
  chmod 0644 "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
  log "$1 ${2:0:7}: $3"
}

fail() { # rev message
  echo "$1" >"$FAILED_FILE"
  write_status failed "$1" "$2"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "homelab-deploy must run as root (use sudo)" >&2
    exit 1
  fi
}

# Fetch the branch and print the newest commit hash.
sync_repo() {
  if [[ ! -d $REPO/.git ]]; then
    git clone --quiet "$REMOTE" "$REPO"
  fi
  git -C "$REPO" fetch --quiet origin "$BRANCH"
  git -C "$REPO" rev-parse FETCH_HEAD
}

# Git pathspecs that select every protected file.
protected_pathspec() {
  local path
  printf '%s\n' .
  for path in "${AGENT_PATHS[@]}"; do
    printf ':(exclude)%s\n' "$path"
  done
}

# True if a repository path belongs to the agent's paths.
is_agent_path() { # path
  local path
  for path in "${AGENT_PATHS[@]}"; do
    if [[ $1 == "$path" || $1 == "$path"/* ]]; then return 0; fi
  done
  return 1
}

# Hash of all protected files at a commit. Fails loudly if the commit cannot be listed.
protected_hash() { # rev
  local listing mode type object path
  listing=$(git -C "$REPO" ls-tree -r --full-tree "$1") || return 1
  [[ -n $listing ]] || return 1
  while IFS=$'\t' read -r meta path; do
    read -r mode type object <<<"$meta"
    if ! is_agent_path "$path"; then
      printf '%s %s %s\t%s\n' "$mode" "$type" "$object" "$path"
    fi
  done <<<"$listing" | sha256sum | cut -d' ' -f1
}

# Evaluate safety invariants of the new configuration; print the names of violated ones.
violated_invariants() { # flake
  nix eval --json "$1#nixosConfigurations.$HOST.config" --apply "
    c: {
      sshEnabled = c.services.openssh.enable;
      tailscaleEnabled = c.services.tailscale.enable;
      deployerTimer = c.systemd.timers ? homelab-deploy;
      adminHasKeys = builtins.length c.users.users.$ADMIN_USER.openssh.authorizedKeys.keys > 0;
      sshPortOpen = !c.networking.firewall.enable || builtins.elem 22 c.networking.firewall.allowedTCPPorts;
    }" | jq -r 'to_entries | map(select(.value != true).key) | join(", ")'
}

healthy() {
  [[ $(tailscale status --json 2>/dev/null | jq -r .BackendState) == Running ]] || return 1
  systemctl is-active --quiet sshd || return 1
  ss -Hltn 'sport = :22' | grep -q . || return 1
  [[ -z $(systemctl list-units --state=failed --no-legend --plain) ]] || return 1
  local unit
  for unit in $HEALTH_UNITS; do
    systemctl is-active --quiet "$unit" || return 1
  done
}

wait_healthy() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT))
  while ((SECONDS < deadline)); do
    if healthy; then return 0; fi
    sleep 5
  done
  return 1
}

# Make a built system the boot default.
promote() { # system-path
  if [[ $(readlink -f "$PROFILE") != "$1" ]]; then
    nix-env --profile "$PROFILE" --set "$1"
    "$1/bin/switch-to-configuration" boot
  fi
}

deploy() { # rev
  local rev=$1 flake new prev missing
  flake="git+file://$REPO?rev=$rev"

  write_status checking "$rev" "evaluating invariants"
  if ! missing=$(violated_invariants "$flake"); then
    fail "$rev" "evaluation failed"
    return
  fi
  if [[ -n $missing ]]; then
    fail "$rev" "invariants violated: $missing"
    return
  fi

  write_status building "$rev" "nix build"
  if ! new=$(nix build --no-link --print-out-paths "$flake#nixosConfigurations.$HOST.config.system.build.toplevel"); then
    fail "$rev" "build failed"
    return
  fi

  prev=$(readlink -f /run/current-system)
  if [[ $new != "$prev" ]]; then
    systemctl reset-failed
    write_status testing "$rev" "activated with switch-to-configuration test"
    if ! "$new/bin/switch-to-configuration" test || ! wait_healthy; then
      write_status rolling-back "$rev" "health check failed"
      "$prev/bin/switch-to-configuration" test || true
      fail "$rev" "health check failed, rolled back to $(basename "$prev")"
      return
    fi
  fi

  promote "$new"
  echo "$rev" >"$DEPLOYED_FILE"
  rm -f "$FAILED_FILE"
  write_status deployed "$rev" "$(basename "$new") is active and boot default"
}

cmd_run() {
  require_root
  exec 9>"$STATE_DIR/lock"
  if ! flock --nonblock 9; then
    log "another deploy is running"
    return
  fi

  # A trigger file has done its job once a run starts.
  rm -f "$TRIGGER_DIR"/*

  local rev
  rev=$(sync_repo)
  if [[ $rev == "$(read_file "$DEPLOYED_FILE")" ]]; then
    log "up to date at ${rev:0:7}"
    return
  fi
  if [[ $rev == "$(read_file "$FAILED_FILE")" ]]; then
    log "${rev:0:7} already failed; push a fix or run: sudo homelab-deploy retry"
    return
  fi

  git -C "$REPO" checkout --quiet --detach "$rev"
  local hash
  if ! hash=$(protected_hash "$rev"); then
    fail "$rev" "could not hash protected files"
    return
  fi
  if [[ $hash != "$(read_file "$APPROVED_FILE")" ]]; then
    echo "$rev" >"$PENDING_FILE"
    write_status awaiting-approval "$rev" "protected files changed; run: sudo homelab-deploy approve"
    return
  fi

  deploy "$rev"
}

# Print the commit waiting for approval; exit 1 if there is none.
pending_rev() {
  local rev
  rev=$(read_file "$PENDING_FILE")
  if [[ -z $rev ]]; then
    echo "Nothing is waiting for approval." >&2
    exit 1
  fi
  echo "$rev"
}

# Record the approval of the protected files exactly as they are at this commit.
approve_rev() { # rev
  local approved_hash
  approved_hash=$(protected_hash "$1") || { echo "Could not hash protected files." >&2; exit 1; }
  echo "$approved_hash" >"$APPROVED_FILE"
  rm -f "$PENDING_FILE" "$FAILED_FILE"
}

cmd_summary() {
  require_root
  local rev base
  local -a spec
  mapfile -t spec < <(protected_pathspec)
  rev=$(pending_rev)
  base=$(read_file "$DEPLOYED_FILE")
  echo "Commit ${rev:0:7} changes protected files (everything except ${AGENT_PATHS[*]}):"
  git -C "$REPO" --no-pager diff --stat=72 "${base:-$EMPTY_TREE}" "$rev" -- "${spec[@]}"
  if [[ -n $base ]]; then
    echo "${REMOTE%.git}/compare/$base...$rev"
  fi
}

# Without an argument: show the summary and ask on the terminal, then deploy in the foreground.
# With a commit (used by the approval bot): approve only if exactly that commit is pending,
# then start the deploy unit without waiting, so the caller may be restarted by the deploy.
cmd_approve() { # [rev]
  require_root
  local rev base answer
  rev=$(pending_rev)
  base=$(read_file "$DEPLOYED_FILE")
  if [[ -n ${1:-} ]]; then
    if [[ $1 != "$rev" ]]; then
      echo "Commit ${1:0:7} is not the one waiting for approval (${rev:0:7})." >&2
      exit 1
    fi
    approve_rev "$rev"
    systemctl start --no-block homelab-deploy.service
    echo "Approved ${rev:0:7}; deploy started."
    return
  fi
  cmd_summary
  echo "Full diff: sudo git -C $REPO diff ${base:-$EMPTY_TREE} $rev -- . ':(exclude)modules/hermes'"
  read -r -p "Approve and deploy ${rev:0:7}? [y/N] " answer
  if [[ $answer != y && $answer != Y ]]; then
    echo "Not approved."
    exit 1
  fi
  approve_rev "$rev"
  cmd_run
}

cmd_retry() {
  require_root
  rm -f "$FAILED_FILE"
  cmd_run
}

cmd_status() {
  read_file "$STATUS_FILE"
  echo "deployed: $(read_file "$DEPLOYED_FILE")"
  echo "pending approval: $(read_file "$PENDING_FILE")"
  echo "last failed: $(read_file "$FAILED_FILE")"
}

case "${1:-run}" in
  run) cmd_run ;;
  approve) cmd_approve "${2:-}" ;;
  summary) cmd_summary ;;
  retry) cmd_retry ;;
  status) cmd_status ;;
  *)
    echo "usage: homelab-deploy [run|approve [rev]|summary|retry|status]" >&2
    exit 2
    ;;
esac
