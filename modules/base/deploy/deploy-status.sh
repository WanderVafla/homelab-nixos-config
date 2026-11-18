# Read-only deploy status as one JSON object, for the owner's desktop widget over SSH.
# Needs no root: the deployer's state files and repository clone are readable by everyone.
# Approving still needs `sudo homelab-deploy approve`.
#
# Set by the Nix wrapper: STATE_DIR, REMOTE and AGENT_SKILLS_DIR (same as homelab-deploy).

REPO="$STATE_DIR/repo"
EMPTY_TREE=4b825dc642cb6eb9a060e54bf8d69288fbee4904
MAX_COMMITS=10

read_file() { cat "$1" 2>/dev/null || true; }

# The clone is owned by root, so git needs it listed as safe for this user.
repo_git() { git -c safe.directory="$REPO" -C "$REPO" --no-pager "$@"; }

status=$(read_file "$STATE_DIR/status.json")
deployed=$(read_file "$STATE_DIR/deployed-rev")
pending=$(read_file "$STATE_DIR/pending-rev")
failed=$(read_file "$STATE_DIR/failed-rev")

commits='[]'
files='[]'
compare=''
if [[ -n $pending ]]; then
  base="${deployed:-$EMPTY_TREE}"
  # Same files as `homelab-deploy summary`: everything except the agent's Markdown skills.
  files=$(repo_git diff --name-status "$base" "$pending" -- . ":(exclude,glob)$AGENT_SKILLS_DIR/**/*.md" |
    jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {status: .[0], path: .[-1]})')
  if [[ -n $deployed ]]; then
    commits=$(repo_git log --max-count="$MAX_COMMITS" --format='%h%x09%s' "$deployed..$pending" |
      jq -R -s 'split("\n") | map(select(. != "") | split("\t") | {rev: .[0], subject: (.[1:] | join("\t"))})')
    compare="${REMOTE%.git}/compare/$deployed...$pending"
  fi
fi

jq -n \
  --argjson status "${status:-null}" \
  --arg deployed "$deployed" \
  --arg pending "$pending" \
  --arg failed "$failed" \
  --argjson commits "$commits" \
  --argjson files "$files" \
  --arg compare "$compare" \
  '{
    state: ($status.state // "unknown"),
    message: ($status.message // ""),
    time: ($status.time // ""),
    deployed: $deployed,
    pending: $pending,
    failed: $failed,
    commits: $commits,
    files: $files,
    compareUrl: $compare
  }'
