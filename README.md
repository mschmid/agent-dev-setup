# Agentic Dev Setup: Claude Code + mise + headroom + herdr

So richtest du eine blanke Maschine (macOS oder Arch Linux) für die Entwicklung mit Agents ein. Die Anleitung deckt Claude Code als Agent ab, **headroom** als lokalen Proxy, der den Kontext komprimiert, **herdr** als Terminal-Workspace-Manager für Agents und **mise** für die Runtimes. Dazu kommen die CLI-Tools, die Agents (und du) ständig brauchen, und eine Statuszeile, die zeigt, ob die Session über headroom läuft.

## Schnellstart

```sh
git clone <dieses-repo> ~/agent-dev-setup   # oder den Ordner kopieren
cd ~/agent-dev-setup
DRY_RUN=1 ./setup.sh   # zeigt nur an, was passieren würde
./setup.sh             # führt alles aus
```

Das Skript kann beliebig oft laufen. Dateien, die es ändert (`~/.zshrc` bzw. `~/.bashrc`, `~/.claude/settings.json`), sichert es vorher als `*.bak-<timestamp>`.

| Variable | Default | Wirkung |
|---|---|---|
| `DRY_RUN` | `0` | `1` ändert nichts und gibt nur die Befehle aus |
| `TARGET_SHELL` | Login-Shell | `zsh` oder `bash`. Bestimmt, ob `~/.zshrc` oder `~/.bashrc` den Shell-Bereich bekommt. Die Login-Shell bleibt unverändert |
| `HEADROOM_PORT` | `8787` | Port des headroom-Proxys |
| `WITH_SERENA` | `0` | `1` registriert zusätzlich den MCP-Server Serena |
| `EXTRA_PLUGINS` | leer | weitere Claude-Plugins, durch Leerzeichen getrennt, z. B. `figma@claude-plugins-official` |

Was danach noch von Hand zu tun ist, gibt das Skript am Ende aus: `claude` starten und einloggen, `gh auth login`, `glab auth login --hostname <host>`, `headroom doctor`.

---

## Was installiert wird und warum

| Tool | Wozu |
|---|---|
| **Claude Code** | der Agent selbst (nativer Installer, aktualisiert sich selbst) |
| **headroom** | lokaler Proxy zwischen Claude Code und der API, komprimiert Tool-Ausgaben und spart Tokens |
| **herdr** | Terminal-Workspaces für Agents: Panes, Worktrees, Agent-Status, Benachrichtigungen |
| **mise** | Runtimes pro Projekt und global (node, pnpm, go, Language Server) |
| **uv** | Python-Tooling, installiert headroom als isoliertes Tool |
| **ripgrep**, **fd** | schnelle Suche in Code und Dateien. Agents greifen darauf bevorzugt zurück |
| **fzf** | interaktive Auswahl: Ctrl+R (History), Ctrl+T (Dateien), Alt+C (cd) |
| **delta** | lesbare Diffs in `git diff`, `git add -p` und lazygit |
| **direnv** | Umgebungsvariablen und Secrets pro Projekt per `.envrc`, statt global in der Shell-rc |
| **just** | einheitliche Befehle pro Repo (`just test`, `just lint`), Agents treffen damit die richtigen Checks |
| **watchexec** | Befehle bei Dateiänderungen neu starten |
| **ast-grep** | strukturelle Suche und Ersetzung über den Syntaxbaum |
| **jq** | JSON auf der Shell, wird auch von der Statuszeile gebraucht |
| **gh**, **glab** | GitHub- und GitLab-CLI |
| **lazygit** | Git-TUI, um Änderungen von Agents zu prüfen |

---

## Manuelle Installation, Schritt für Schritt

Die einzelnen Schritte entsprechen den Abschnitten in `setup.sh`.

### 1. Systempakete

**macOS**
```sh
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
brew install git zsh jq ripgrep fd fzf git-delta direnv just watchexec \
  gh glab lazygit ast-grep uv mise herdr
```

**Arch Linux / Omarchy**
```sh
sudo pacman -Syu --needed git curl base-devel python libsecret jq \
  ripgrep fd fzf git-delta direnv just watchexec github-cli glab lazygit ast-grep uv mise
yay -S --needed herdr-bin                         # ohne AUR-Helper: curl -fsSL https://herdr.dev/install.sh | sh
```

Unter **Omarchy** (erkannt an `~/.local/share/omarchy`) nimmt das Skript `pacman -S` statt `-Syu`. Systemupdates laufen dort über `omarchy-update`, also am besten vorher einmal ausführen. Weil Omarchy `yay` mitbringt, kommt herdr direkt aus dem AUR (`herdr-bin`).

`python` brauchst du für den herdr-Hook von Claude Code. `libsecret` dient als Git-Credential-Store, ohne ihn findet die Statuszeile keinen GitLab-Token.

### 2. Runtimes mit mise

```sh
mise use -g node@lts pnpm@latest go@latest \
  npm:typescript npm:typescript-language-server go:golang.org/x/tools/gopls
```

Die Language Server sind für die LSP-Plugins von Claude Code gedacht (siehe 6.). Projektspezifische Versionen gehören in eine `mise.toml` im Repo.

### 3. Claude Code und headroom

```sh
curl -fsSL https://claude.ai/install.sh | bash          # landet in ~/.local/bin/claude
uv tool install --python 3.13 'headroom-ai[all]'        # landet in ~/.local/bin/headroom
```

### 4. Shell (zsh oder bash)

Folgendes kommt ans Ende von `~/.zshrc` bzw. `~/.bashrc`. Das Skript verwaltet den Bereich zwischen den Markern `# >>> agent-dev-setup >>>` und `# <<< agent-dev-setup <<<`. Ausgewählt wird nach der Login-Shell, also zsh auf dem Mac und bash unter Omarchy. Mit `TARGET_SHELL` lässt sich das überschreiben.

Jeder Hook ist abgesichert. Hat die Distribution ihn schon weiter oben in der rc-Datei eingerichtet, wird er übersprungen. Omarchy aktiviert mise zum Beispiel schon in seinen Bash-Defaults. Ein doppelter `PROMPT_COMMAND` oder `precmd` entsteht so nicht.

**zsh** (`~/.zshrc`)
```sh
export PATH="$HOME/.local/bin:$PATH"
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
(( $+functions[_mise_hook] )) || eval "$(mise activate zsh)"
(( $+functions[fzf-history-widget] )) || source <(fzf --zsh)
(( $+functions[_direnv_hook] )) || eval "$(direnv hook zsh)"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
```

**bash** (`~/.bashrc`)
```sh
export PATH="$HOME/.local/bin:$PATH"
declare -F _mise_hook >/dev/null || eval "$(mise activate bash)"
declare -F __fzf_history__ >/dev/null || eval "$(fzf --bash)"
declare -F _direnv_hook >/dev/null || eval "$(direnv hook bash)"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
```

Die Statuszeile und die Hooks von Claude Code laufen ohnehin mit `bash`. Welche Login-Shell du nutzt, spielt für sie keine Rolle.

### 5. git und lazygit

```sh
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.navigate true          # n/N springt zwischen Dateien
git config --global delta.line-numbers true
git config --global merge.conflictStyle zdiff3   # Konflikte zeigen auch den gemeinsamen Ursprung
# nur Linux:
git config --global credential.helper /usr/lib/git-core/git-credential-libsecret
```

Für Agents ändert sich durch delta nichts. Git schaltet den Pager nur ein, wenn die Ausgabe in ein Terminal geht.

**lazygit** (Pfad: `lazygit --print-config-dir`, also `~/Library/Application Support/lazygit/` auf dem Mac und `~/.config/lazygit/` unter Linux). Welches Format gilt, hängt von der Version ab:

```yaml
# ältere Versionen (z. B. 0.55)
git:
  paging:
    colorArg: always
    pager: delta --dark --paging=never
```
```yaml
# neuere Versionen mit Pager-Liste
git:
  pagers:
    - colorArg: always
      pager: delta --dark --paging=never
```

Das Skript erkennt das Format selbst. Eine bestehende, nicht leere Konfiguration lässt es aber unangetastet.

### 6. Claude Code konfigurieren

**Statuszeile:** `statusline-command.sh` nach `~/.claude/` kopieren und in `~/.claude/settings.json` eintragen:

```json
{
  "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" },
  "env": { "ENABLE_TOOL_SEARCH": "true" }
}
```

**Globale Anweisungen:** `claude/CLAUDE.md` nach `~/.claude/CLAUDE.md` kopieren. Die Datei sagt Claude, welche Tools es nutzen soll, die es sonst selten wählt (ast-grep, `just`, `glab`, mise). Eine vorhandene Datei überschreibt `setup.sh` nicht.

**headroom-Routing:**
```sh
headroom init -g --port 8787 claude
claude mcp add -s user -e HEADROOM_PROXY_URL=http://127.0.0.1:8787 \
  headroom -- ~/.local/bin/headroom mcp serve
```
`headroom init` trägt `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` in `settings.json` ein. Außerdem richtet es Hooks ein, die den Proxy bei Bedarf starten. Danach läuft jedes `claude` über headroom, `headroom wrap claude` brauchst du nicht mehr.

**Plugins:**
```sh
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install superpowers@claude-plugins-official
claude plugin install typescript-lsp@claude-plugins-official
claude plugin install gopls-lsp@claude-plugins-official
```

**herdr:**
```sh
herdr integration install claude      # meldet herdr den Status jeder Claude-Session
herdr plugin link "$PWD/herdr/lazygit-pane"   # lazygit rechts in jedem neuen Workspace
```

---

## Statuszeile

```
 my-app  | Opus 5.5 | master* | ctx 40% | ⛰ −914.5k tok (3.7%) | 🔗 !42
```

| Feld | Bedeutung |
|---|---|
| ` my-app ` | aktuelles Verzeichnis (nur der letzte Teil, damit es auch in schmalen Panes lesbar bleibt) |
| `Opus 5.5` | Modell |
| `master*` | Git-Branch, `*` = uncommittete Änderungen |
| `ctx 40%` | belegter Anteil des Kontextfensters |
| `⛰ −914.5k tok (3.7%)` | Session läuft über headroom, eingesparte Tokens |
| `⛰ proxy down` | `ANTHROPIC_BASE_URL` zeigt auf localhost, aber der Proxy antwortet nicht |
| `⛰ off` | Session geht direkt zu Anthropic |
| `🔗 !42` | offener GitLab-MR für den Branch, anklickbar (OSC-8-Link) |

Was du zur Statuszeile wissen solltest:
- **headroom:** Die Zahl kommt aus der „display session“ des Proxys (`/stats`). Sie gilt für **alle** Clients, die über diesen Proxy laufen, und beginnt nach 60 Minuten ohne Aktivität wieder bei null. Getrennte Zahlen pro Claude-Session liefert headroom nicht.
- **MR-Link:** Die Statuszeile holt den Token per `git credential fill` und fragt damit die GitLab-API ab. Gecacht wird 10 Minuten, wenn ein MR gefunden wurde, sonst 1 Minute. Funktioniert nur mit einem Credential-Helper (macOS: Schlüsselbund, Linux: libsecret) und einem `origin`, der per HTTPS oder SSH auf GitLab zeigt.
- Läuft auf macOS und Linux.

---

## headroom: was du wissen solltest

- **Nur für die lokale CLI.** Sessions auf claude.ai/code laufen in der Cloud und erreichen deinen Proxy nicht. Die Desktop-App überschreibt `ANTHROPIC_BASE_URL`.
- **Remote Control ist gesperrt**, solange `ANTHROPIC_BASE_URL` auf einen eigenen Endpoint zeigt. Für solche Sessions musst du Claude ohne headroom starten. Weil die URL in `settings.json` steht, reicht es wahrscheinlich nicht, die Umgebungsvariable in der Shell zu leeren. Ein Kandidat (nicht getestet):
  ```sh
  claude --settings '{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}'
  ```
- **Der Hook vor jedem Bash-Aufruf kostet etwa 0,3 s pro Aufruf.** `headroom init` legt ihn als `PreToolUse`-Hook auf `Bash` an. Falls dich das stört, kannst du ihn entfernen und den Hook auf `SessionStart` behalten. Möglicherweise legt headroom ihn bei einem späteren `init` wieder an:
  ```sh
  jq 'del(.hooks.PreToolUse[] | select(.hooks[].command | test("headroom init hook")))' \
    ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
  ```
  Alternativ lässt du den Proxy dauerhaft als Dienst laufen: `headroom install start`.
- **Fällt der Proxy aus, geht in Claude nichts mehr**, weil die URL global gesetzt ist. Den Zustand prüfst du mit `headroom doctor`.
- **Dashboard:** `headroom dashboard -p 8787` oder http://127.0.0.1:8787/dashboard. Die Einsparungen über längere Zeit zeigt `headroom savings`.
- **Verwaiste Proxys:** Nach `headroom wrap` bleiben Proxys manchmal weiterlaufen. Finden kannst du sie mit `lsof -nP -iTCP -sTCP:LISTEN | grep -i python`.

## herdr: Tipps

- `herdr worktree create`: legt einen Git-Worktree an und öffnet gleich einen Workspace samt Pane dazu. Gut, um mehrere Tickets parallel zu bearbeiten.
- Agents per Skript steuern: `herdr agent list | prompt | wait | read`. Ein Beispiel: Agent A ein Review machen lassen und mit `herdr agent wait` auf das Ende warten.
- Shortcuts laufen über die Prefix-Taste (`prefix+1..9` wechselt den Tab, `prefix+tab`, `prefix+shift+…`). Die vollständige Liste steht in der Hilfe in herdr selbst.
- Plugin `herdr/lazygit-pane`: Jeder neue Workspace in einem Git-Repo bekommt rechts ein Pane mit lazygit. Wechselst du im linken Pane per `cd` in ein anderes Repo, startet lazygit dort neu (Abfrage jede Sekunde). `q` beendet lazygit ganz. Abschalten mit `herdr plugin disable local.lazygit-pane`.
- Konfiguration: `~/.config/herdr/config.toml`, prüfen mit `herdr config check`, neu laden mit `herdr server reload-config`.

## Shortcuts in Claude Code

| Taste | Wirkung |
|---|---|
| Shift+Tab | Modus wechseln (normal, Auto-Accept, Plan) |
| Esc Esc | zu einer früheren Nachricht zurückspringen, auf Wunsch auch mit den Code-Änderungen |
| Ctrl+G | Prompt in `$EDITOR` bearbeiten |
| Ctrl+O | vollständigen Verlauf anzeigen |
| Ctrl+B | laufenden Bash-Befehl in den Hintergrund schicken |
| Ctrl+] | letztes Artifact öffnen |
| `!befehl` | Shell-Befehl in der Session ausführen |
| `@pfad` | auf eine Datei verweisen |
| `claude -c` / `claude -r` | letzte Session fortsetzen / Session aus einer Liste wählen |

## Secrets

API-Keys gehören nicht als `export` in `~/.zshrc` oder `~/.bashrc`. Dort sieht sie jeder Prozess und jeder Agent in jeder Shell. Besser ist eine `.envrc` pro Projekt:

```sh
# ~/Work/<projekt>/.envrc
export GOOGLE_API_KEY="$(security find-generic-password -s google-api-key -w)"   # macOS-Schlüsselbund
```
```sh
direnv allow
```
`.envrc` kommt in `.gitignore` bzw. in `~/.config/git/ignore`.
