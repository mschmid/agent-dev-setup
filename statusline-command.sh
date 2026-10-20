#!/bin/bash
# Claude Code statusLine: dir | model | git branch (dirty marker) | context % | GitLab MR link
# The working directory comes first so it stays readable in narrow split panes.
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Working directory: leaf name only, so it survives narrow split panes
dir="${cwd##*/}"
[ -z "$dir" ] && dir="${cwd/#$HOME/~}"

# Git branch + dirty marker (skip optional locks so we never block other git processes)
branch=""
if git --no-optional-locks -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ] && [ -n "$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null)" ]; then
    branch="${branch}*"
  fi
fi

# Context usage
ctx=""
if [ -n "$used_pct" ]; then
  ctx=$(printf "%.0f" "$used_pct")
fi

# GitLab MR for the current branch (clickable OSC 8 hyperlink).
# Resolved via GitLab API (token from `git credential fill`), cached on disk so
# the statusline never hits the API on every render. TTL: 10 min when an MR was
# found, 1 min when none exists yet (so a freshly created MR shows up quickly).
mr_iid=""
mr_url=""
if [ -n "$branch" ]; then
  raw_branch="${branch%\*}"
  remote=$(git --no-optional-locks -C "$cwd" remote get-url origin 2>/dev/null)
  # SSH → HTTPS (git@host:group/repo.git → https://host/group/repo)
  if [[ "$remote" == git@* ]]; then
    remote="${remote#git@}"
    remote="https://${remote/://}"
  fi
  remote="${remote%.git}"
  if [[ "$remote" == https://* ]]; then
    host="${remote#https://}"
    host="${host%%/*}"
    proj_path="${remote#https://"$host"/}"
    cache_dir="$HOME/.claude/cache"
    mkdir -p "$cache_dir"
    key=$(printf '%s|%s' "$remote" "$raw_branch" | md5 -q 2>/dev/null || printf '%s|%s' "$remote" "$raw_branch" | md5sum | cut -d' ' -f1)
    cache_file="$cache_dir/statusline-mr-$key"

    entry=""
    if [ -f "$cache_file" ]; then
      entry=$(cat "$cache_file" 2>/dev/null)
      # GNU stat (Linux) first, BSD stat (macOS) as fallback
      mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
      age=$(( $(date +%s) - mtime ))
      ttl=600
      [ "$entry" = "none" ] && ttl=60
      [ "$age" -ge "$ttl" ] && entry=""
    fi

    if [ -z "$entry" ]; then
      token=$(printf 'protocol=https\nhost=%s\n\n' "$host" | GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true git credential fill 2>/dev/null | sed -n 's/^password=//p')
      if [ -n "$token" ]; then
        enc_proj=$(printf '%s' "$proj_path" | jq -sRr @uri)
        enc_branch=$(printf '%s' "$raw_branch" | jq -sRr @uri)
        entry=$(curl -s --max-time 2 -H "PRIVATE-TOKEN: $token" \
          "https://$host/api/v4/projects/$enc_proj/merge_requests?source_branch=$enc_branch&state=opened&per_page=1" 2>/dev/null |
          jq -r 'if type=="array" and length>0 then "\(.[0].iid)\t\(.[0].web_url)" else "none" end' 2>/dev/null)
        [ -z "$entry" ] && entry="none"
        printf '%s' "$entry" > "$cache_file"
      fi
    fi

    if [ -n "$entry" ] && [ "$entry" != "none" ]; then
      mr_iid="${entry%%$'\t'*}"
      mr_url="${entry#*$'\t'}"
    fi
  fi
fi

# Headroom: is this session routed through the local proxy, and how much did it save?
# Savings come from the proxy's display session (shared by all clients of that proxy,
# resets after 60 min of inactivity), not from this Claude session alone.
hr=""
hr_state=""
case "$ANTHROPIC_BASE_URL" in
  http://127.0.0.1:*|http://localhost:*)
    stats=$(curl -s --max-time 0.5 "${ANTHROPIC_BASE_URL%/}/stats" 2>/dev/null)
    hr=$(printf '%s' "$stats" | jq -r '.display_session // empty |
      def human: if . >= 1000000 then "\((. / 100000 | floor) / 10)M"
                 elif . >= 1000 then "\((. / 100 | floor) / 10)k"
                 else tostring end;
      "−\(.tokens_saved | human) tok (\(.savings_percent | . * 10 | round / 10)%)"' 2>/dev/null)
    if [ -n "$hr" ]; then hr_state="up"; else hr_state="down"; fi
    ;;
  *) hr_state="off" ;;
esac

# Dim colors (readable on dark and light terminals)
RESET="\033[0m"
DIM_CYAN="\033[2;36m"
DIM_BLUE="\033[2;34m"
DIM_YELLOW="\033[2;33m"
DIM_MAGENTA="\033[2;35m"
DIM_GREEN="\033[2;32m"
# Working directory: bold white on black, so it stands out as the first entry
DIR_STYLE="\033[1;97;40m"
SEP="${RESET} \033[2m|\033[0m "

line="${DIR_STYLE} ${dir} ${RESET}"
line="${line}${SEP}${DIM_CYAN}${model}${RESET}"
if [ -n "$branch" ]; then
  line="${line}${SEP}${DIM_YELLOW}${branch}${RESET}"
fi
if [ -n "$ctx" ]; then
  line="${line}${SEP}${DIM_MAGENTA}ctx ${ctx}%${RESET}"
fi
case "$hr_state" in
  up)   line="${line}${SEP}${DIM_GREEN}⛰ ${hr}${RESET}" ;;
  down) line="${line}${SEP}\033[2;31m⛰ proxy down${RESET}" ;;
  off)  line="${line}${SEP}\033[2m⛰ off${RESET}" ;;
esac
if [ -n "$mr_url" ]; then
  # OSC 8 hyperlink: \e]8;;URL\a TEXT \e]8;;\a
  line="${line}${SEP}${DIM_GREEN}🔗 \033]8;;${mr_url}\a!${mr_iid}\033]8;;\a${RESET}"
fi

printf "%b" "$line"
