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

ok "Done. Verify with:  claude-switch help"
