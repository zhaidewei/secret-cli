# secret

A small, dependency-light CLI for storing API keys, tokens, and passwords in the
operating system's credential store. It is designed for shell scripts and coding
agents: values are retrieved only when a command needs them, without committing
them to `.env` files or keeping them in a long-lived exported environment.

- macOS: Keychain via the built-in `security` CLI
- Windows: Credential Manager via the native Win32 Credential API
- No daemon or separate master password
- Bash and zsh completion on macOS
- Loud failures for missing, empty, or locked credentials

## Install

### macOS

Clone and run the installer:

```bash
git clone https://github.com/zhaidewei/secret-cli.git
cd secret-cli
./install.sh
```

The installer links `secret` into `~/.local/bin` and installs Bash/zsh
completion. Make sure `~/.local/bin` is on `PATH`.

For a script-only install:

```bash
curl -fsSL https://raw.githubusercontent.com/zhaidewei/secret-cli/main/bin/secret \
  -o ~/.local/bin/secret
chmod +x ~/.local/bin/secret
```

Requires Bash 4+.

### Windows

Download `bin/secret.ps1` and optionally `bin/secret.cmd` into the same
directory, then add that directory to `PATH`. With the launcher installed:

```powershell
secret --version
secret add github-pat-personal "Personal GitHub token"
```

You can also invoke the PowerShell script directly:

```powershell
pwsh -File .\secret.ps1 list
```

The Windows implementation uses only built-in .NET and
`Advapi32.dll`; no PowerShell module is required. It supports Windows
PowerShell 5.1 and PowerShell 7+. Windows Credential Manager limits generic
credential blobs to 2560 bytes.

> The Windows implementation has been reviewed and statically checked, but the
> v0.2.0 release has not yet been exercised on a physical Windows machine.
> Please report Windows-specific problems in GitHub Issues.

## Usage

```text
secret list                   # names only
secret list -l                # names and descriptions
secret get <name>             # value on stdout, without a trailing newline
secret add <name> [desc]      # hidden prompt, or read from stdin
secret update <name> [desc]   # replace value; omitted desc is preserved
secret rm <name>              # delete
secret --version
secret --help
```

Examples:

```bash
secret add aliyun-prod-access-key "Aliyun production access key"

ALIBABA_CLOUD_ACCESS_KEY_ID=$(secret get aliyun-prod-access-key) \
  aliyun ecs DescribeInstances

pbpaste | secret add databricks-dev-token "Databricks development PAT"
```

PowerShell:

```powershell
secret add aliyun-prod-access-key "Aliyun production access key"
$env:ALIBABA_CLOUD_ACCESS_KEY_ID = secret get aliyun-prod-access-key
aliyun ecs DescribeInstances
Remove-Item Env:ALIBABA_CLOUD_ACCESS_KEY_ID
```

## Why this is agent-friendly

- Credentials stay in the OS credential store instead of source files.
- `get` is non-interactive and writes only the value to stdout.
- Missing or empty values fail with a non-zero exit code.
- `list -l` provides a self-describing inventory without exposing values.
- A fixed namespace keeps managed entries separate from unrelated credentials.

Use command substitution carefully: a value substituted into a command line may
still be visible to that process or to operating-system process inspection.
Prefer a tool's stdin/file-descriptor credential support when it has one.

## Storage model

| Platform | Namespace | Backend |
| --- | --- | --- |
| macOS | `account=agent-secrets` | Login Keychain generic passwords |
| Windows | `TargetName=agent-secrets:<name>` | Credential Manager generic credentials |

Descriptions are stored as the Keychain comment on macOS and the credential
comment on Windows.

## Naming convention

A useful convention is:

```text
<vendor>-<environment>-<type>
```

Examples: `github-pat-personal`, `databricks-dev-token`,
`aliyun-cn-dev-rds-password`.

## Uninstall

On macOS:

```bash
./uninstall.sh
```

This removes only installed links. Stored credentials remain in Keychain. On
Windows, remove the downloaded scripts from `PATH`; stored credentials remain
in Credential Manager.

## License

MIT.
