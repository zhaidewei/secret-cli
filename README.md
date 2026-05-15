# secret

A tiny CLI for stashing API keys, tokens, and database passwords in
the macOS Keychain — and pulling them back out without ever putting
the value into a shell variable, a `.env` file, or your shell history.

```bash
# Stash it once
secret add aliyun-prod-access-key "Aliyun prod root AK"

# Use it without leaking
ALIBABA_CLOUD_ACCESS_KEY_ID=$(secret get aliyun-prod-access-key) \
  aliyun ecs DescribeInstances
```

Single Bash file, ~230 lines, wraps the `security` binary that already
ships with macOS. No daemon, no extra agent, no master password.

## The problem

If you do anything with cloud APIs, databases, or AI agents, you end
up holding a lot of long-lived credentials. They tend to settle in
exactly the wrong places:

- `.env` and `~/.zshrc`, where one wrong `git add` commits them.
- `export PGPASSWORD=...`, which then lives in your shell environment
  and is readable by every child process for the rest of the session.
- Your shell history, where `mysql -p'…'` and friends sit in plain text.
- A Keepass / Notion / 1Password vault that you have to click through
  every time you want to use one in a terminal.

The deeper issue: there is no friction-free way to **inject a secret
into one command and only that command** without it spilling into the
ambient environment.

## Why the usual fixes fall short

A few things people reach for, and where each one stops short:

- **dotenv files** — encryption story is "don't commit it"; one
  mistake and it's on GitHub. Also still `export`-ed into the shell.
- **`pass` / `gopass`** — strong tools, but you bring in GPG keys, an
  agent, and a separate trust root. Overkill if your laptop already
  has an OS keychain.
- **1Password CLI** — great if you already pay for it. Adds a
  network-backed dependency and a session token that has to be kept
  alive.
- **Raw `security` calls** — the macOS binary works, but the UX is
  awful: `security find-generic-password -a foo -s bar -w` is hard to
  type, hard to script, returns nothing on a missing key, and
  silently mixes in with every other thing macOS has stored in your
  Keychain (Wi-Fi passwords, Safari logins, certificates).

## What `secret` does

It's a thin wrapper around `security add-generic-password` /
`find-generic-password` / `delete-generic-password`, plus four design
choices that turn it into something pleasant to use:

- **OS-level encrypted storage.** Values live in
  `~/Library/Keychains/login.keychain-db`, encrypted at rest, unlocked
  by your macOS login password. No new daemon, no master password.
- **Inject in place, don't pollute the environment.** The recommended
  pattern is `$(secret get name)` — the value flows into one command
  and dies with it. It never enters your shell environment, your
  history, or any child process beyond the one you intended.
- **Namespaced from the rest of your Keychain.** Every entry is stored
  with the same fixed `account=agent-secrets` field. `secret list`
  filters on that field, so you only ever see things this tool put
  there — not your saved Wi-Fi passwords.
- **Fails loudly.** `secret get` exits 1 with a message on stderr if
  the entry is missing, empty, or the Keychain is locked. It will not
  silently return an empty string and let your script send an
  unauthenticated request to production.

That's the whole pitch.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/zhaidewei/secret-cli/main/bin/secret \
  -o ~/.local/bin/secret
chmod +x ~/.local/bin/secret
```

Make sure `~/.local/bin` is on your `PATH`. Requires macOS (uses the
`security` binary) and Bash 4+.

Or clone and symlink:

```bash
git clone https://github.com/zhaidewei/secret-cli.git
ln -s "$PWD/secret-cli/bin/secret" ~/.local/bin/secret
```

## Usage

```bash
secret list                   # names only
secret list -l                # names + descriptions, table-aligned
secret get <name>             # print value to stdout (no trailing newline)
secret add <name> [desc]      # hidden prompt, or read from stdin
secret update <name> [desc]   # replace value; omit desc to keep it
secret rm <name>              # delete
secret --help                 # full help with examples
```

A few real patterns:

```bash
# Add from the clipboard without echoing the value
pbpaste | secret add databricks-dev-token "Databricks dev workspace PAT"

# psql without the password ever entering shell history
PGPASSWORD=$(secret get aliyun-cn-dev-rds-password) \
  psql -h pgm-xxx.pg.rds.aliyuncs.com -U dbuser -d mydb

# Browse what you have
secret list -l
```

### Naming convention

Pick a scheme and stick to it. The one I use:

```
<vendor>-<env>-<type>
```

Examples: `aliyun-main-access-key-id`, `databricks-dev-token`,
`github-pat-personal`, `aliyun-cn-dev-rds-password`. It keeps
`secret list` readable as the number of entries grows past a dozen.

## Why this is agent-friendly

The shape ends up being a particularly good fit for coding agents
and other shell-out tools:

- **Credentials never enter the agent's context.** When the agent
  runs `cmd --token=$(secret get foo)`, the shell substitutes the
  value before `exec` — the literal string the agent sees, logs, and
  replays is `$(secret get foo)`. No raw credential ever lands in
  the conversation transcript.
- **Smallest blast radius for shell-out.** Agents shell out
  constantly. Anything you `export` lives the whole session and is
  inherited by every sibling tool call. `$(secret get …)` lives one
  command and dies — if the agent goes off the rails later, the
  credential isn't sitting in the environment to be exfiltrated.
- **Loud failure is what an agent needs.** Agents lack the human
  "wait, why is this empty?" instinct. Exit 1 plus a stderr message
  lets the agent notice and ask for help, instead of silently firing
  an unauthenticated request at production.
- **Self-describing inventory.** `secret list -l` lets the agent
  discover what's available and what each entry is for — the
  description field doubles as machine-readable metadata, so you
  don't have to maintain a separate `credentials.md` for the agent
  to keep in sync.
- **Non-interactive by design.** `secret get` works with no tty;
  `secret add` reads from stdin if it's piped. Nothing stalls on
  "press any key to continue."

## How it works

Each entry is one generic-password record:

| Keychain field | Value |
| --- | --- |
| `service` | `<name>` you pass on the CLI |
| `account` | `agent-secrets` (fixed) |
| `password` | the value |
| `comment` | optional description |

`list` reads `security dump-keychain` and filters on
`account=agent-secrets` with a small awk program — that's why it shows
your secrets and not every Wi-Fi password macOS has ever seen.

## License

MIT.
