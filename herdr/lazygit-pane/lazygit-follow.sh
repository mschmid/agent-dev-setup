#!/bin/sh
# Run lazygit for the repo the source pane is in, and restart it whenever that
# pane cds into another repo. Quitting lazygit (q) ends the loop.
herdr="${HERDR_BIN_PATH:-herdr}"
src="$1"
next=$(mktemp)
trap 'rm -f "$next"' EXIT

src_repo() {
  cwd=$("$herdr" pane get "$src" 2>/dev/null | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
  [ -n "$cwd" ] && git -C "$cwd" rev-parse --show-toplevel 2>/dev/null
}

# Poll the source pane; on a repo change remember the new repo and stop lazygit.
watch() {
  while sleep 1; do
    r=$(src_repo) || continue
    [ "$r" = "$1" ] && continue
    printf '%s' "$r" >"$next"
    pkill -TERM -x -P $$ lazygit
    return
  done
}

repo=$(src_repo) || exit 0
while :; do
  : >"$next"
  watch "$repo" &
  watcher=$!
  lazygit -p "$repo"
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  repo=$(cat "$next")
  [ -n "$repo" ] || break
  clear
done
