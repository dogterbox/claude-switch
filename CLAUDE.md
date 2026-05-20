# CLAUDE.md

Project context for Claude Code working in this repo.

## Scope

A single bash script (`claude-switch`) plus installer and docs. The whole
tool lives in one file. **Do not split it into multiple files** — the
single-file shape is a feature (drop-in install, easy to audit).

## Hard constraints

- **macOS only.** Anything Linux/Windows is out of scope. The `security`
  CLI and macOS Keychain are non-negotiable dependencies.
- **Bash 3.2 compatible.** The system `/bin/bash` on macOS is 3.2 and we
  target it. **Avoid:** associative arrays (`declare -A`), `mapfile`/
  `readarray`, `${var^^}` / `${var,,}`, `&>` redirect shorthand, `wait -n`.
  `[[ ]]`, `local`, `printf '%q'` are fine.
- **`jq` is optional.** All `account_*` functions must be no-ops when `jq`
  is missing (`has_jq`). Never make jq a hard dependency.

## Keychain ACL: `-A` is intentional

`kc_save` uses `security add-generic-password -A` (trust any app, no
prompts). This is the documented "strategy B" trade-off in the README —
**do not "fix" it** by switching to `-T <path>` without discussing first.
Per-binary ACLs would prompt repeatedly because the `claude` binary path
varies across installs (Homebrew x86/arm, npm, manual).

## Where data lives

- **Active token**: macOS Keychain service `Claude Code-credentials`
  (read by Claude Code itself, never inside `~/.claude/`).
- **Per-profile backup tokens**: `Claude Code-credentials-<name>`.
- **Active `~/.claude.json`**: top-level cache Claude Code reads on
  launch for `oauthAccount`, `/status`, `/usage`, etc. **It is NOT a
  shared file across profiles** — `claude-switch use` swaps it. If you
  forget to swap it, `/status` and `/usage` keep showing the previous
  account until an API refresh fires.
- **Per-profile `~/.claude.json` snapshot**:
  `~/.claude-profiles/<name>/.claude-root.json` (written by `root_stash`,
  restored by `root_restore`).
- **Per-profile account-info snapshot**: `<name>/.account.json` — a
  smaller `oauthAccount`-only copy used by `list`/`current` to print the
  email. Decorative; the root snapshot is the load-bearing one.
- **Per-profile dir**: `~/.claude-profiles/<name>/` (target of the
  `~/.claude` symlink).

## Conventions

- User-facing strings are **English only**. Emojis allowed as status icons
  (✅ ⚠️ ❌ ⭐️ 🔑 💾 ℹ️ 👤 🏢 📁) — don't add new emojis without reason.
- The `legacy` profile name is reserved and cannot be removed.
- Every command function should exit 0 on success. A common pitfall: a
  trailing `[[ ... ]] && echo ...` returns non-zero when the test is
  false. Wrap in `if ... then ... fi` to preserve exit status.

## Before committing

```sh
bash -n claude-switch       # syntax check
bash -n install.sh
```

Then exercise the behavioral changes manually — there's no test suite.
Especially verify: `claude-switch help`, `list`, `current` all exit 0.

## Out of scope

- Linux/Windows ports (would need a different secret backend).
- Token decoding (JWT parse). Email comes from `~/.claude.json`, not from
  the token itself.
- Mid-session migration. A `--force` switch never migrates a running
  Claude Code session — only future launches see the new profile.
