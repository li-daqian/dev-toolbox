# Personal Agent Setup

`scripts/install-agent-setup.sh` manages the global instruction template and
`last30days` from `mvanhorn/last30days-skill` for Codex and Claude Code.
Matt Pocock skills are managed separately by Codex:

```bash
codex plugin marketplace add mattpocock/skills
codex plugin add mattpocock-skills@mattpocock
```

The repository no longer provides Matt skill installation, removal, profile
manifests, or scheduled updates. The Agent installer does not manage plugins.

## Commands and destinations

```bash
# Instructions + last30days; defaults to user scope and both Agents
./scripts/install-agent-setup.sh setup
./scripts/install-agent-setup.sh instructions --agent codex
./scripts/install-agent-setup.sh skills --scope project --agent claude
./scripts/install-agent-setup.sh setup --dry-run
./scripts/install-agent-setup.sh skills --offline
```

Instructions always install at user scope, including with `setup --scope project`:

- Codex: `${CODEX_HOME:-~/.codex}/AGENTS.md`
- Claude Code: `${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md`

| Scope | Codex skills | Claude Code skills |
| --- | --- | --- |
| User | `~/.agents/skills` | `${CLAUDE_CONFIG_DIR:-~/.claude}/skills` |
| Project | `<git-root>/.agents/skills` | `<git-root>/.claude/skills` |

`--project` selects an explicit Git repository; otherwise project scope uses the
current directory. The old personal/work profile selection has been removed.

Linux, macOS, and WSL use Bash, Git, and directory symlinks. Windows Git Bash
uses managed directory copies. Native PowerShell is not supported.

## Ownership and safety

Unknown files, directories, and links are never overwritten. Managed links must
resolve inside the selected source; managed copies carry a provider-and-skill
marker. Project scope reuses an exact managed user-scope installation, and
rejects a conflicting user-scope implementation. The complete last30days skill
directory is installed, including scripts and references.

Instruction writes are content-aware. Equal content is left untouched; changed
regular files are backed up. Symlinks and non-regular instruction targets are
rejected. Codex users are warned if `AGENTS.override.md` masks `AGENTS.md`.
All Agent destinations are preflighted before installation begins; unexpected
failures after writes begin do not have automatic rollback.

## Sources and updates

The managed last30days checkout defaults to
`${XDG_DATA_HOME:-~/.local/share}/codex-skill-sources/last30days-skill` at `main`.
Normal runs fetch the requested ref. `--offline` requires an existing checkout;
`--dry-run` neither fetches nor writes and reports unverified source contents
when the checkout is absent.

Override the source with `--last30days-ref`, `--last30days-source-root`, or
`--last30days-source-dir`. An external source directory is never fetched or
modified. `AGENT_SETUP_LAST30DAYS_SOURCE_DIR` also supplies an external source.
The research engine requires Python 3.12+. Installation reuses `yt-dlp` from
PATH, or installs its official GitHub release into `~/.local/bin`. Offline
installation fails if this dependency is missing. Optional data sources may
need credentials or tools configured through the upstream setup workflow.

Scheduled updates support Linux and systemd-enabled WSL, at user scope only:

```bash
./scripts/install-agent-setup.sh auto-update enable --agent both
./scripts/install-agent-setup.sh auto-update status
./scripts/install-agent-setup.sh auto-update disable
```

The timer records the last30days ref, source, and Agent target. It updates skills
only; external source directories are rejected. Use a persistent checkout and
re-enable the timer after moving it. Other platforms and project installations
are updated by rerunning the installer manually.

`install-global-agent-charter.sh` remains a wrapper with preview by default and
`--apply` to install instructions. There is no general uninstall command.
