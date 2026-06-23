#!/usr/bin/env bash
# claude-switch installer
# Usage:
#   ./install.sh                  # installs to /usr/local/bin
#   ./install.sh ~/.local/bin     # installs to a custom directory
#   ./install.sh --uninstall      # removes the installed binary

set -euo pipefail

DEFAULT_TARGET="/usr/local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/claude-switch"

die()  { printf '\xe2\x9d\x8c %s\n' "$*" >&2; exit 1; }
ok()   { printf '\xe2\x9c\x85 %s\n' "$*"; }
info() { printf '\xe2\x84\xb9\xef\xb8\x8f  %s\n' "$*"; }

[[ "$(uname -s)" == "Darwin" ]] || die "claude-switch supports macOS only"
[[ -f "$SOURCE" ]]              || die "Cannot find $SOURCE"

if [[ "${1:-}" == "--uninstall" ]]; then
    target="${2:-$DEFAULT_TARGET}"
    bin="$target/claude-switch"
    if [[ -e "$bin" ]]; then
        rm -f "$bin"
        ok "Removed $bin"
    else
        info "Nothing to remove at $bin"
    fi
    exit 0
fi

target="${1:-$DEFAULT_TARGET}"
[[ -d "$target" ]] || die "Target directory '$target' does not exist"

dest="$target/claude-switch"
install -m 0755 "$SOURCE" "$dest"
ok "Installed $dest"

# PATH check
if ! printf '%s' ":$PATH:" | grep -q ":$target:"; then
    info "Note: '$target' is not in your PATH."
    info "Add it (e.g. in ~/.zshrc):  export PATH=\"$target:\$PATH\""
fi

# Optional: warn about a leftover shell function shadowing the binary
if command -v zsh >/dev/null 2>&1 && zsh -ic 'typeset -f claude-switch >/dev/null 2>&1' 2>/dev/null; then
    info "A shell function named 'claude-switch' is defined in your zsh init."
    info "It will shadow this binary — remove it from ~/.zshrc."
fi

# ---------- Shell function setup ---------------------------------------------

SHELL_FUNC='
# claude-switch: auto-eval env subcommand
claude-switch() {
  if [[ "${1:-}" == "env" ]]; then
    eval "$(command claude-switch env "${2:-}")"
  else
    command claude-switch "$@"
  fi
}'

append_shell_func() {
    local rc="$1"
    if grep -q 'command claude-switch env' "$rc" 2>/dev/null; then
        info "Shell function already present in $rc — skipping"
    else
        printf '\n%s\n' "$SHELL_FUNC" >> "$rc"
        ok "Appended shell function to $rc"
        info "Run: source $rc"
    fi
}

printf '\nInstall shell function for '\''claude-switch env'\'' auto-eval?\n'
printf '  1) zsh  (~/.zshrc)\n'
printf '  2) bash (~/.bashrc)\n'
printf '  3) both\n'
printf '  4) skip\n'
printf 'Choice [1-4]: '
read -r shell_choice </dev/tty
case "${shell_choice:-4}" in
    1) append_shell_func "$HOME/.zshrc" ;;
    2) append_shell_func "$HOME/.bashrc" ;;
    3) append_shell_func "$HOME/.zshrc"; append_shell_func "$HOME/.bashrc" ;;
    *) info "Skipping shell function setup" ;;
esac

# ---------- First-time profile setup ----------------------------------------

BASE_DIR="$HOME/.claude-profiles"
TARGET_LINK="$HOME/.claude"
ACTIVE_KEY="Claude Code-credentials"
KEY_PREFIX="Claude Code-credentials-"

if [[ -L "$TARGET_LINK" ]]; then
    info "~/.claude is already managed by claude-switch — skipping profile setup"
elif [[ -d "$TARGET_LINK" ]]; then
    info "Setting up claude-switch for the first time..."
    mkdir -p "$BASE_DIR"
    mv "$TARGET_LINK" "$BASE_DIR/legacy"
    ln -s "$BASE_DIR/legacy" "$TARGET_LINK"
    ok "Moved ~/.claude → ~/.claude-profiles/legacy"

    if security find-generic-password -s "$ACTIVE_KEY" >/dev/null 2>&1; then
        tok=$(security find-generic-password -s "$ACTIVE_KEY" -w 2>/dev/null)
        security delete-generic-password -s "${KEY_PREFIX}legacy" >/dev/null 2>&1 || true
        security add-generic-password -s "${KEY_PREFIX}legacy" -a "$USER" -w "$tok" -A
        ok "Snapshotted token to profile 'legacy'"
    else
        info "No active token found — log in to Claude Code and the token will be saved automatically on your first profile switch"
    fi
else
    info "~/.claude not found — skipping profile setup (run after Claude Code has been launched once)"
fi

ok "Done. Run 'claude-switch list' to verify."
