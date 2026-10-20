#!/usr/bin/env bash
# Bootstrap an agentic dev setup on a blank macOS or Arch Linux machine:
# Claude Code, mise, headroom, herdr, CLI tools, shell/git/lazygit integration, statusline.
#
# Idempotent: safe to re-run. Existing files are backed up before they are changed.
#
#   ./setup.sh                 install and configure everything
#   DRY_RUN=1 ./setup.sh       print what would happen, change nothing
#   WITH_SERENA=1 ./setup.sh   additionally register the Serena MCP server
#   TARGET_SHELL=bash ./setup.sh   integrate with bash/zsh instead of the login shell
#   EXTRA_PLUGINS="figma@claude-plugins-official" ./setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-0}"
WITH_SERENA="${WITH_SERENA:-0}"
HEADROOM_PORT="${HEADROOM_PORT:-8787}"
# Shell to integrate with: the login shell by default (zsh on macOS, bash on Omarchy).
TARGET_SHELL="${TARGET_SHELL:-$(basename "${SHELL:-bash}")}"
case "$TARGET_SHELL" in
  zsh)  SHELL_RC="${SHELL_RC:-$HOME/.zshrc}" ;;
  bash) SHELL_RC="${SHELL_RC:-$HOME/.bashrc}" ;;
  *)    printf 'Unsupported shell: %s (use TARGET_SHELL=zsh|bash)\n' "$TARGET_SHELL" >&2; exit 1 ;;
esac
PLUGINS=(
  superpowers@claude-plugins-official
  typescript-lsp@claude-plugins-official
  gopls-lsp@claude-plugins-official
)
# shellcheck disable=SC2206
PLUGINS+=(${EXTRA_PLUGINS:-})

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  + %s\n' "$*"; else "$@"; fi; }
# Like run, but for a pipeline or anything else that needs a shell.
runsh() { if [ "$DRY_RUN" = 1 ]; then printf '  + %s\n' "$1"; else sh -c "$1"; fi; }

backup() {
  [ -f "$1" ] || return 0
  run cp "$1" "$1.bak-$(date +%Y%m%d%H%M%S)"
}

# Replace (or append) a marker-delimited block in a file.
write_block() {
  local file="$1" content="$2"
  local begin="# >>> agent-dev-setup >>>" end="# <<< agent-dev-setup <<<"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  + write block into %s:\n%s\n' "$file" "$content" | sed 's/^/    /'
    return
  fi
  touch "$file"
  backup "$file"
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '$0==b{skip=1} !skip{print} $0==e{skip=0}' "$file" >"$tmp"
  printf '%s\n%s\n%s\n' "$begin" "$content" "$end" >>"$tmp"
  mv "$tmp" "$file"
}

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  [ -f /etc/arch-release ] && OS=arch || die "Only Arch Linux is supported on Linux." ;;
  *)      die "Unsupported OS: $(uname -s)" ;;
esac
export PATH="$HOME/.local/bin:$PATH"

# --- 1. System packages ------------------------------------------------------
log "System packages ($OS)"
if [ "$OS" = mac ]; then
  xcode-select -p >/dev/null 2>&1 || { run xcode-select --install; die "Finish the Xcode CLT install, then re-run."; }
  if ! have brew; then
    runsh 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  run brew install git jq ripgrep fd fzf git-delta direnv just watchexec \
    gh glab lazygit ast-grep uv mise herdr
else
  # Omarchy manages system upgrades itself (omarchy-update), so only add missing packages there.
  if [ -d "$HOME/.local/share/omarchy" ]; then
    pacman_sync=(-S)
  else
    pacman_sync=(-Syu)
  fi
  run sudo pacman "${pacman_sync[@]}" --needed --noconfirm git curl base-devel python libsecret jq \
    ripgrep fd fzf git-delta direnv just watchexec github-cli glab lazygit ast-grep uv mise
  if ! have herdr; then
    # herdr is only in the AUR; without an AUR helper fall back to the upstream installer.
    if have yay; then
      run yay -S --needed --noconfirm herdr-bin
    else
      runsh 'curl -fsSL https://herdr.dev/install.sh | sh'
    fi
  fi
fi

# --- 2. Language runtimes via mise --------------------------------------------
log "Runtimes via mise (node, pnpm, go, language servers)"
run mise use -g node@lts pnpm@latest go@latest \
  npm:typescript npm:typescript-language-server go:golang.org/x/tools/gopls
eval "$(mise activate bash --shims)"

# --- 3. Claude Code and headroom ----------------------------------------------
log "Claude Code"
have claude || runsh 'curl -fsSL https://claude.ai/install.sh | bash'

log "headroom"
have headroom || run uv tool install --python 3.13 'headroom-ai[all]'

# --- 4. Shell integration ------------------------------------------------------
log "$TARGET_SHELL integration ($SHELL_RC)"
# Each hook is guarded, so it is skipped when the distro rc (e.g. Omarchy's bash defaults)
# has already set it up earlier in the file.
if [ "$TARGET_SHELL" = zsh ]; then
  write_block "$SHELL_RC" "$(cat <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
(( $+functions[_mise_hook] )) || eval "$(mise activate zsh)"
# fzf key bindings: Ctrl+R history, Ctrl+T files, Alt+C cd
(( $+functions[fzf-history-widget] )) || source <(fzf --zsh)
(( $+functions[_direnv_hook] )) || eval "$(direnv hook zsh)"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
EOF
)"
else
  write_block "$SHELL_RC" "$(cat <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
declare -F _mise_hook >/dev/null || eval "$(mise activate bash)"
# fzf key bindings: Ctrl+R history, Ctrl+T files, Alt+C cd
declare -F __fzf_history__ >/dev/null || eval "$(fzf --bash)"
declare -F _direnv_hook >/dev/null || eval "$(direnv hook bash)"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
EOF
)"
fi

# --- 5. git and lazygit --------------------------------------------------------
log "git (delta, zdiff3)"
run git config --global core.pager delta
run git config --global interactive.diffFilter 'delta --color-only'
run git config --global delta.navigate true
run git config --global delta.line-numbers true
run git config --global merge.conflictStyle zdiff3
# The statusline resolves GitLab MRs via `git credential fill`, so Linux needs a store.
if [ "$OS" = arch ] && [ -z "$(git config --global --get credential.helper || true)" ]; then
  run git config --global credential.helper /usr/lib/git-core/git-credential-libsecret
fi

log "lazygit (delta as pager)"
lg_dir="$(lazygit --print-config-dir 2>/dev/null || echo "$HOME/.config/lazygit")"
lg_cfg="$lg_dir/config.yml"
if [ -s "$lg_cfg" ]; then
  warn "$lg_cfg is not empty, leaving it alone. Add delta as pager by hand (see README)."
elif grep -a -q 'yaml:"pagers"' "$(command -v lazygit)"; then
  # lazygit with the list-style `pagers` key
  run mkdir -p "$lg_dir"
  runsh "printf 'git:\n  pagers:\n    - colorArg: always\n      pager: delta --dark --paging=never\n' > '$lg_cfg'"
else
  run mkdir -p "$lg_dir"
  runsh "printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > '$lg_cfg'"
fi

# --- 6. Claude Code configuration ---------------------------------------------
log "Claude Code statusline and settings"
settings="$HOME/.claude/settings.json"
run mkdir -p "$HOME/.claude"
run cp "$SCRIPT_DIR/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
# Global instructions: only a starting point, never overwrite an existing CLAUDE.md.
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  warn "$HOME/.claude/CLAUDE.md exists, leaving it alone (template: claude/CLAUDE.md)"
else
  run cp "$SCRIPT_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi
if [ "$DRY_RUN" != 1 ]; then
  [ -f "$settings" ] || echo '{}' >"$settings"
  backup "$settings"
  tmp="$(mktemp)"
  jq --arg cmd "bash $HOME/.claude/statusline-command.sh" \
    '.statusLine = {type: "command", command: $cmd} | .env.ENABLE_TOOL_SEARCH = "true"' \
    "$settings" >"$tmp" && mv "$tmp" "$settings"
else
  printf '  + set statusLine and env.ENABLE_TOOL_SEARCH in %s\n' "$settings"
fi

log "headroom routing for Claude Code (port $HEADROOM_PORT)"
# Sets ANTHROPIC_BASE_URL in settings.json and installs the hooks that keep the proxy running.
run headroom init -g --port "$HEADROOM_PORT" claude
if ! claude mcp get headroom >/dev/null 2>&1; then
  run claude mcp add -s user -e "HEADROOM_PROXY_URL=http://127.0.0.1:$HEADROOM_PORT" \
    headroom -- "$HOME/.local/bin/headroom" mcp serve
fi

log "Claude Code plugins"
run claude plugin marketplace add anthropics/claude-plugins-official || true
for p in "${PLUGINS[@]}"; do
  run claude plugin install "$p" || warn "plugin $p failed"
done

if [ "$WITH_SERENA" = 1 ] && ! claude mcp get serena >/dev/null 2>&1; then
  log "Serena MCP"
  run claude mcp add -s user serena -- uvx --from serena-agent serena start-mcp-server \
    --project-from-cwd --context claude-code --open-web-dashboard False
fi

log "herdr integration for Claude Code"
run herdr integration install claude
log "herdr plugin: lazygit pane in every new workspace"
run herdr plugin link "$SCRIPT_DIR/herdr/lazygit-pane"

# --- Done ------------------------------------------------------------------------
log "Done. Manual steps left:"
cat <<EOF
  1. Open a new terminal (or: exec $TARGET_SHELL)
  2. claude                 -> log in on first start
  3. gh auth login
  4. glab auth login --hostname <your GitLab host>
  5. headroom doctor        -> check that the proxy and routing are fine
  6. herdr                  -> start the workspace manager, run claude inside it
EOF
