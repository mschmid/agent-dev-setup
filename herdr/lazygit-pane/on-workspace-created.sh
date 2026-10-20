#!/bin/sh
# Split the root pane of a new workspace and run lazygit on the right,
# but only when the workspace lives in a git repo. lazygit follows the
# left pane into other repos (see lazygit-follow.sh).
set -eu
herdr="${HERDR_BIN_PATH:-herdr}"
cwd=$(printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" | sed -n 's/.*"workspace_cwd":"\([^"]*\)".*/\1/p')
[ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

pane=$("$herdr" pane split "$HERDR_PANE_ID" --direction right --cwd "$cwd" --no-focus |
  sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p')
"$herdr" pane run "$pane" sh "$HERDR_PLUGIN_ROOT/lazygit-follow.sh" "$HERDR_PANE_ID" >/dev/null
