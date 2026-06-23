# claude-switch

> Manage multiple Claude Code accounts on macOS — switch globally or run in parallel.

`claude-switch` keeps multiple Claude Code accounts side by side. It supports two modes:

- **Swap mode** — switch the global active account (`use`). One account at a time; no extra dependencies.
- **Parallel mode** — inject a per-process token so two VS Code windows (or two terminals) can use different accounts simultaneously. Requires `jq`.

```
$ claude-switch list
📁 Claude Profiles:
  ⭐️  legacy    👤  alice@example.com
  -   work      👤  bob@example.com
  -   personal  [login required]
```

---

## Why this exists

Claude Code on macOS stores its OAuth token in **macOS Keychain** under
`Claude Code-credentials`, not inside `~/.claude/`. A directory-only profile
switcher rotates settings, history, and skills — but the active login stays
global, so every profile authenticates as the same account.

`claude-switch` swaps both things at once: the `~/.claude` symlink **and** the
Keychain entry.

---

## Requirements

| Dependency | When needed |
|---|---|
| macOS | always — uses `security` CLI and Keychain |
| bash 3.2 | always — the system `/bin/bash` works |
| `jq` | parallel mode only (`env`, `run`, `refresh`, `wrapper`) |

`jq` is pre-installed on most developer setups; otherwise `brew install jq`.

---

## Installation

```sh
git clone <repo-url> ~/MySpaces/claude-switch
cd ~/MySpaces/claude-switch
./install.sh                  # installs to /usr/local/bin by default
./install.sh ~/.local/bin     # or specify a target directory
```

The installer moves `~/.claude` → `~/.claude-profiles/legacy`, creates the
symlink, and snapshots your current token into the `legacy` profile.

Verify:

```sh
claude-switch status
```

If you had a `claude-switch` shell function in `~/.zshrc`, remove it — a
function in `.zshrc` shadows the binary in `PATH`.

---

## Swap mode

One global active account at a time. No `jq` required.

### Commands

```
claude-switch create <name>           Create a new empty profile
claude-switch list                    List all profiles and account emails
claude-switch status                  Show the active profile and account
claude-switch use <name> [--force]    Switch to a profile
claude-switch rename <old> <new>      Rename a profile
claude-switch delete <name>           Delete a profile (directory + Keychain token)
claude-switch help                    Show usage
```

### Add a second account

```sh
# Quit Claude Code first
claude-switch create work
claude-switch use work
# → Keychain entry cleared, ~/.claude points to 'work'

# Launch Claude Code and log in with the second account.
# When you switch away, claude-switch saves 'work's token automatically.
```

### Switch back

```sh
claude-switch use legacy
# → 'work's token saved, 'legacy's token restored, ~/.claude swaps
```

### How `use` works

1. Snapshot the current profile:
   - active Keychain token → `Claude Code-credentials-<current>`
   - `oauthAccount` from `~/.claude.json` → `<current>/.account.json`
   - whole `~/.claude.json` → `<current>/.claude-root.json`
2. Restore the target profile's token into the active Keychain slot (or clear
   it if the target has no saved token — Claude Code prompts to log in).
3. Restore the target profile's `~/.claude.json` snapshot (or remove the file
   if none exists — Claude Code recreates it on next launch).
4. Repoint `~/.claude` → `~/.claude-profiles/<name>/`.

Step 3 matters because Claude Code reads `~/.claude.json` at launch for
`/status`, `/usage`, and `oauthAccount`. Without it, those surfaces show the
previous account until the next API refresh.

---

## Parallel mode

Run two accounts at the same time by injecting `CLAUDE_CODE_OAUTH_TOKEN` and
`CLAUDE_CONFIG_DIR` as process-level environment variables — they override
the global Keychain entry at runtime. Tokens are refreshed automatically.

**Requires `jq`.**

### Commands

```
claude-switch env <name>              Print export statements (for eval or direnv)
claude-switch run <name> [-- cmd...]  Set env and exec a command (default: claude)
claude-switch refresh <name>          Refresh the profile's token and write it back
claude-switch wrapper <name>          Write a launcher script, print its path
```

### Terminal / tmux

```sh
# Inject into the current shell session
eval "$(claude-switch env work)"
claude                              # runs as 'work' account

# One-shot without eval
claude-switch run personal -- claude chat
```

### direnv (per-directory, automatic)

Add to `.envrc` in a repo:

```sh
eval "$(claude-switch env work)"
```

Every `cd` into that directory activates the `work` account.

### VS Code — per-window account

Generate a wrapper script once per profile:

```sh
claude-switch wrapper work
# → /Users/<you>/.claude-profiles/work/launch

claude-switch wrapper personal
# → /Users/<you>/.claude-profiles/personal/launch
```

In each repo's `.vscode/settings.json`:

```jsonc
// repo-a/.vscode/settings.json  →  work account
{ "claudeCode.claudeProcessWrapper": "/Users/<you>/.claude-profiles/work/launch" }

// repo-b/.vscode/settings.json  →  personal account
{ "claudeCode.claudeProcessWrapper": "/Users/<you>/.claude-profiles/personal/launch" }
```

Open each repo in a separate VS Code window. The wrapper reads a fresh token
from Keychain at each launch — no secret is stored in the settings file.

> VS Code's `claudeCode.claudeProcessWrapper` setting is `scope=window`. A single
> multi-root workspace cannot split accounts per-folder; each window is one account.

### Token refresh

Tokens expire after ~24 hours. `env`, `run`, and `wrapper` all call the refresh
engine automatically before returning a token. You can also warm the cache manually:

```sh
claude-switch refresh work
✅ Token for 'work' is fresh
```

If the refresh token is dead (requires a new login):

```
❌ Could not refresh token for 'work' — run 'claude-switch use work' and log in to Claude Code
```

---

## Where the data lives

```
~/.claude                        → symlink to the active profile directory
~/.claude.json                   Claude Code's top-level cache; swapped by `use`
~/.claude-profiles/
├── legacy/
│   ├── .account.json            oauthAccount snapshot (used by list/status)
│   ├── .claude-root.json        full ~/.claude.json snapshot (restored on switch)
│   ├── launch                   wrapper script (created by `wrapper` command)
│   ├── settings.json
│   ├── history.jsonl
│   ├── projects/
│   └── ...
├── work/
└── personal/
```

Keychain entries (visible in Keychain Access.app, search "Claude"):

```
Claude Code-credentials              ← active slot, read by Claude Code
Claude Code-credentials-legacy       ← backup for 'legacy' profile
Claude Code-credentials-work
Claude Code-credentials-personal
```

---

## Keychain ACL

`claude-switch` writes Keychain entries with `-A` (any application may read
without prompting). Trade-off:

- ✅ No permission dialogs when Claude Code or the wrapper reads the token.
- ⚠️  Any process running as your user can read the token via `security`.

This matches the existing exposure of `~/.claude.json` and `~/.claude/`, which
are already user-readable. If you prefer per-binary ACLs, edit `kc_save()` and
replace `-A` with `-T /usr/bin/security -T "$(which claude)"` — but note that
the `claude` binary path varies by install method, which is why `-A` is the
default.

---

## Safety notes

- `use` refuses to switch while Claude Code is running (process check). Pass
  `--force` to override; the running session keeps its in-memory state.
- Switching never modifies profile directory contents — only the symlink moves.
- `delete` removes the profile directory and its Keychain token. No trash recovery.
- `legacy` is a reserved profile name and cannot be deleted.

---

## Troubleshooting

**`list` shows no emails** — install `jq` (`brew install jq`).

**Keychain prompts during a switch** — the existing entry has a restrictive ACL
from a previous install. Switch to any other profile and back once; `kc_save`
rewrites the entry with `-A` and silences future prompts.

**Profile shows no email** — account info hasn't been captured yet. Switch away
and back; the auto-save on switch populates `.account.json`.

**`~/.claude` exists and is not a symlink** — leftover real directory from an
older install:

```sh
mkdir -p ~/.claude-profiles
mv ~/.claude ~/.claude-profiles/legacy
ln -s ~/.claude-profiles/legacy ~/.claude
```

**`env`/`run`/`refresh`/`wrapper` fails with "jq required"** — `brew install jq`.

**`refresh` returns "Could not refresh token"** — the OAuth refresh token has
expired. Run `claude-switch use <name>`, launch Claude Code, and log in once.
That writes a fresh token pair back to Keychain.

---

## Limitations

- **macOS only.** The `security` CLI and Keychain have no Linux/Windows equivalent here.
- **`~/.claude.json` is snapshot-on-switch, not live-synced.** State written by
  Claude Code between two switches belongs to the currently active profile.
- **No mid-session migration.** `--force` won't move a running session; only
  future launches see the new profile.
- **Switching to a profile with no snapshot clears `~/.claude.json`.** Claude
  Code recreates it on next launch (the onboarding banner may appear once).
- **Parallel mode shares history across windows on the same profile.** Per-session
  files are keyed by session ID so data loss is unlikely, but concurrent config
  writes are not isolated.
- **Token refresh internals are undocumented.** The `client_id`
  (`9d1c250a-e61b-44d9-88ed-5944d1962f5e`) and endpoint
  (`https://platform.claude.com/v1/oauth/token`) were extracted from Claude Code
  v2.1.186. A future release may change them; file an issue if refresh stops working.

---

## Development

Single bash script; no external build step.

```sh
bash -n claude-switch    # syntax check
bash -n install.sh
```

Manually verify after any change: `claude-switch help`, `list`, `status` all exit 0.

---

## License

MIT — see [LICENSE](LICENSE).
