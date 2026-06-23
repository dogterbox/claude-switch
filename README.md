# claude-switch

> Switch between Claude Code accounts on macOS — for real.

`claude-switch` lets you keep multiple Claude Code (Anthropic) accounts side by
side and switch between them with one command. Unlike directory-only profile
switchers, it also swaps the OAuth token stored in **macOS Keychain**, so each
profile is genuinely a different logged-in account — no manual re-login.

```
$ claude-switch list
📁 Claude Profiles:
  ⭐️  legacy    👤  alice@example.com
  -   work      👤  bob@example.com
  -   personal  [login required]
```

---

## Motivation

I started with a small zsh function that swapped `~/.claude/` between profile
directories via a symlink. It looked like it worked — until I noticed that
**every profile was still logged in as the same account**.

Why? Claude Code on macOS doesn't store its OAuth token inside `~/.claude/`.
It stores it in **macOS Keychain** under the service name
`Claude Code-credentials`. The directory swap was rotating settings, history,
custom skills/agents, and per-project state — but the active login was
system-wide, shared across every profile.

So a "real" account switcher has to swap *two* things at once: the directory
**and** the Keychain entry. That's what `claude-switch` does.

(Along the way, the original zsh function turned out to have a latent bug too:
`[ "$x" == "$y" ]` is fine in bash, but zsh's `EQUALS` option tries to resolve
the literal `==` as a path lookup for a command named `=`, producing the
mysterious `claude-switch:40: = not found`. Fixed by moving to `[[ ... ]]`.
That fix is what made me look closer at what the function was really doing.)

## How it works

For each profile `<name>`:

| What                          | Where                                                              |
| ----------------------------- | ------------------------------------------------------------------ |
| Config / history / skills     | `~/.claude-profiles/<name>/`                                       |
| OAuth token (backup slot)     | macOS Keychain: `Claude Code-credentials-<name>`                   |
| Account cache (oauthAccount)  | `~/.claude-profiles/<name>/.account.json`                          |
| Full `~/.claude.json` backup  | `~/.claude-profiles/<name>/.claude-root.json`                      |

On `claude-switch use <name>`:

1. Snapshot the **current** profile's state:
   - active Keychain token → `Claude Code-credentials-<current>`
   - `oauthAccount` from `~/.claude.json` → `<current>/.account.json`
   - whole `~/.claude.json` → `<current>/.claude-root.json`
2. Restore the **target** profile's token from
   `Claude Code-credentials-<name>` into the active Keychain slot (or
   clear it if the target has no saved token — Claude Code will prompt
   to log in).
3. Restore the **target** profile's `~/.claude.json` snapshot back to
   `~/.claude.json` (or remove the file entirely if the target has no
   snapshot — Claude Code recreates it on next launch).
4. Repoint the `~/.claude` symlink to `~/.claude-profiles/<name>/`.

Why step 3 matters: Claude Code reads `~/.claude.json` on launch for
`oauthAccount`, `/status`, `/usage`, and other account-scoped state. If
only the Keychain token is swapped, `/status` and `/usage` still show the
previous account's cached identity until the next API refresh. Swapping
the whole file keeps every account-scoped surface consistent.

When you launch Claude Code next, it reads the new token from Keychain,
the new `~/.claude.json` cache, and the new config from `~/.claude/` —
a different account, no login needed.

## Requirements

- **macOS** (uses the `security` CLI and the system Keychain)
- **`jq`** — only used to display emails in `list` / `status`. Everything
  else still works without it. (Pre-installed on most setups; otherwise
  `brew install jq`.)
- **`bash`** — the system `/bin/bash` (3.2) is fine. The script uses `[[ ]]`
  but no other bash 4+ features.

## Installation

### Option 1 — install script

```sh
git clone <repo-url> ~/MySpaces/claude-switch
cd ~/MySpaces/claude-switch
./install.sh                       # installs to /usr/local/bin by default
# or specify a target:
./install.sh ~/.local/bin
```

### Option 2 — manual

```sh
install -m 0755 claude-switch /usr/local/bin/claude-switch
```

> Note: manual install skips the automatic profile setup. Run `./install.sh` once
> to let it migrate `~/.claude`, then copy the binary wherever you need it.

### Verify

```sh
claude-switch help
```

If a previous version of `claude-switch` exists as a shell function in your
`~/.zshrc` (the inspiration for this project), remove that block — a function
defined in `.zshrc` shadows the binary in `PATH`.

## Usage

```
claude-switch create <name>               Create a new empty profile
claude-switch list                        List profiles + account info
claude-switch status                      Show the active profile + account info
claude-switch use <name> [--force]        Switch to profile <name>
claude-switch rename <old> <new>          Rename a profile
claude-switch delete <name>               Delete a profile (directory + token)
claude-switch help                        Show usage

# Parallel mode (requires jq)
claude-switch env <name>                  Print export statements for the profile
claude-switch run <name> [-- cmd...]      Run a command as the profile (default: claude)
claude-switch refresh <name>              Refresh and re-save the profile's token
claude-switch wrapper <name>              Write a wrapper script, print its path
```

### First-time setup

The installer handles this automatically. When you run `./install.sh`, it:

1. Moves `~/.claude` → `~/.claude-profiles/legacy`
2. Creates the `~/.claude` symlink
3. Snapshots your active token into the `legacy` profile

Confirm everything looks right after installing:

```sh
claude-switch status
```

### Add a second account

```sh
# Quit Claude Code (the macOS app or the CLI) first
claude-switch create work
claude-switch use work
# → Active Keychain entry is cleared
# → ~/.claude points to the empty 'work' directory

# Launch Claude Code and log in with the second account
# When you switch away later, claude-switch will save 'work's token automatically
```

### Switch back

```sh
claude-switch use legacy
# 'work's token is saved, 'legacy's token is restored, ~/.claude swaps
```

### Day-to-day inspection

```sh
$ claude-switch status
⭐️  Profile     legacy
🔑  Token       active
👤  Account     alice@example.com
🏢  Org         Personal (admin)

$ claude-switch list
📁 Claude Profiles:
  ⭐️  legacy  👤  alice@example.com
  -   work    👤  bob@example.com
```

## Where the data lives

```
~/.claude                           → symlink to one of ~/.claude-profiles/*
~/.claude.json                      Claude Code's top-level cache. Restored
                                    from the active profile's snapshot on
                                    every `claude-switch use`.
~/.claude-profiles/
├── legacy/
│   ├── .account.json               oauthAccount snapshot — used by
│   │                               `claude-switch list` / `status`
│   ├── .claude-root.json           full ~/.claude.json snapshot — restored
│   │                               into ~/.claude.json on switch
│   ├── settings.json
│   ├── settings.local.json
│   ├── history.jsonl
│   ├── projects/                   per-project session state
│   ├── sessions/
│   ├── skills/   commands/   agents/   plugins/
│   └── ...                         (whatever else Claude Code writes)
├── work/
└── personal/
```

In Keychain Access.app, search for "Claude":

```
Claude Code-credentials              ← active, read by Claude Code
Claude Code-credentials-legacy       ← backup slot for the 'legacy' profile
Claude Code-credentials-work
Claude Code-credentials-personal
```

## Keychain ACL: "trust all"

When `claude-switch` writes to Keychain it uses
`security add-generic-password -A`, which means "any application may read
this item without prompting." The trade-off:

- ✅ Claude Code reads its credential silently across switches; no recurring
  permission dialogs.
- ⚠️  Any process running as your user can read the OAuth token via the
  `security` CLI. For credentials on your own machine this matches the
  reality that `~/.claude.json` and `~/.claude/` are already user-readable.

If you prefer per-binary ACLs, edit `kc_save()` in the script and replace
`-A` with explicit `-T` paths, e.g.:

```sh
security add-generic-password -s "$service" -a "$USER" -w "$password" \
    -T /usr/bin/security -T "$(which claude)"
```

Note that the path of the `claude` binary varies by install method
(`/opt/homebrew/bin/claude` on Apple Silicon Homebrew, `/usr/local/bin/claude`
on Intel Homebrew, npm-installed paths, etc.).

## Safety notes

- The script **refuses** to `use` a profile while Claude Code is running
  (it greps the process list for `claude` and `Claude.app`). Pass `--force`
  to override; the running session keeps its in-memory state but any new
  writes will land in the newly-linked profile directory.
- Switching never touches the contents of any profile directory — only the
  `~/.claude` symlink moves.
- Per-profile backup tokens stay in Keychain after a switch. Switching back
  restores them; no need to log in again.
- `claude-switch delete <name>` removes the profile directory and its backup
  Keychain entry. There is no trash recovery.
- `legacy` is a reserved profile name and cannot be deleted.

## Troubleshooting

**`= not found` from the old zsh function** — that's zsh's `EQUALS` option
misreading `[ "$x" == "$y" ]`. Either move the test to `[[ ... ]]` or switch
to this tool (which already uses `[[ ... ]]`).

**`list` doesn't show emails** — install `jq`. Without it the script still
works, it just can't read `.account.json`.

**Keychain prompts during a switch** — happens once when the existing
`Claude Code-credentials` entry has a restrictive ACL inherited from a
previous install. Switch to any other profile and back; the delete-then-add
inside `kc_save` rewrites the entry with `-A` and silences future prompts.

**Profile shows no email** — the account info hasn't been captured yet.
Switch away from that profile and back; the auto-save on switch will populate it.

**`~/.claude exists and is not a symlink`** — you have a real `~/.claude`
directory left over from an older install. Move it into the profile
structure first:

```sh
mkdir -p ~/.claude-profiles
mv ~/.claude ~/.claude-profiles/legacy
ln -s ~/.claude-profiles/legacy ~/.claude
```

## Parallel mode — two accounts at once

The `use` command switches a single global login. Parallel mode lets two
windows/terminals run **different accounts simultaneously** by setting
`CLAUDE_CODE_OAUTH_TOKEN` per-process (the env var overrides Keychain at
runtime) and `CLAUDE_CONFIG_DIR` pointing at the profile directory.

Requires `jq` (`brew install jq`).

### terminal / tmux / direnv

```sh
# Activate in the current shell
eval "$(claude-switch env work)"
claude           # runs as 'work' account

# Or launch a single command without eval
claude-switch run work -- claude chat
```

With [direnv](https://direnv.net/), add to `.envrc`:

```sh
eval "$(claude-switch env work)"
```

### VS Code — per-repo account

In each repo's `.vscode/settings.json`:

```jsonc
{
  "claudeCode.claudeProcessWrapper": "/Users/<you>/.claude-profiles/work/launch"
}
```

Generate the wrapper script once:

```sh
claude-switch wrapper work
# → /Users/<you>/.claude-profiles/work/launch
```

The wrapper reads a fresh token from Keychain every time VS Code starts a
Claude Code process — no secret is stored in the settings file.

Open Repo A (pointing at `work`) and Repo B (pointing at `personal`) in
separate VS Code windows; each gets its own account automatically.

### Token refresh

Tokens expire after ~24 hours. `env`, `run`, and `wrapper` all refresh
automatically when the token is within 60 seconds of expiry. You can also
refresh on demand:

```sh
claude-switch refresh work
```

If the refresh token itself is expired (rare), you'll get a clear error:

```
❌ Could not refresh token for 'work' — run 'claude-switch use work' and log in to Claude Code
```

### Known limitations (parallel mode)

- **`jq` is required.** The four parallel commands die immediately without it.
- **Two windows on the *same* profile share `history.jsonl` / `projects/`.**
  Per-session files are keyed by session ID so data corruption is unlikely,
  but concurrent config writes to the same profile are not isolated.
- **VS Code `scope=window` only.** A single multi-root workspace cannot
  split accounts per-folder — each *window* is one account.
- **`client_id` and token endpoint** (`9d1c250a-…`, `platform.claude.com`)
  are undocumented internals extracted from the Claude Code v2.1.186
  binary. A future release may change them; file an issue if refresh breaks.

## Limitations

- **macOS only.** Linux uses `libsecret` or a different keystore — the
  Keychain commands here don't translate. A Linux port would need a separate
  backend.
- **`~/.claude.json` is snapshot-on-switch, not live-synced.** Claude Code
  rewrites this file every launch with the active account's data;
  `claude-switch` captures it at switch time. Between two switches, any
  state Claude Code writes belongs to whichever profile is currently
  active — that's the intended isolation.
- **No mid-session migration.** A `--force` switch while Claude Code is
  running won't relocate the running session — only future launches see
  the new profile.
- **Switching to a profile with no saved snapshot clears `~/.claude.json`.**
  Claude Code rebuilds the file on next launch (you may re-see the
  onboarding banner once).

## Development

The whole tool is a single bash script (`claude-switch`). Conventions:

- Bash 3.2 compatible (no associative arrays, no `mapfile`).
- All user-facing strings in English; emojis are language-neutral status icons.
- Keychain access funneled through `kc_read` / `kc_save` / `kc_delete` /
  `kc_exists` so the ACL strategy is in one place.
- Account-info display is a separate concern from token swapping —
  `account_stash` and `account_field` are no-ops when `jq` isn't installed.

Syntax-check before committing:

```sh
bash -n claude-switch
```

## License

MIT — see [LICENSE](LICENSE).
