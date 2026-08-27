# Personal Agent Setup

`scripts/install-agent-setup.sh` is the public installer for this repository's
personal Agent environment. It manages one global instruction template and a
reviewed subset of the upstream `mattpocock/skills` repository.

## Design model

Skill selection and installation location are independent dimensions:

| Dimension | Values | Meaning |
| --- | --- | --- |
| Profile | `personal`, `work` | Selects the exact desired skill manifest |
| Scope | `user`, `project` | Selects a user-wide or Git-project destination |
| Agent target | `codex`, `claude`, `both` | Selects which supported Agent receives the installation |

The `personal` manifest contains the explicitly reviewed upstream promoted
`engineering` and `productivity` skills. The smaller `work` manifest contains
`grilling`, `grill-me`, and `diagnosing-bugs`. New upstream skills never enter a
profile merely because a directory appeared upstream.

Instructions are deliberately not profile- or project-specific. They are
installed only at user scope:

- Codex: `${CODEX_HOME:-~/.codex}/AGENTS.md`
- Claude Code: `${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md`

Skills use the Agent-specific discovery paths:

| Scope | Codex | Claude Code |
| --- | --- | --- |
| User | `~/.agents/skills` | `${CLAUDE_CONFIG_DIR:-~/.claude}/skills` |
| Project | `<git-root>/.agents/skills` | `<git-root>/.claude/skills` |

## Platform support

- Linux and macOS: Bash, Git, and directory symlinks.
- Windows: WSL or Git Bash only. Native PowerShell is not supported.
- WSL uses Linux semantics and symlinks.
- Native Windows Git Bash uses managed directory copies because native symlink
  creation is not reliably available without additional Windows configuration.

This installer guarantees that the upstream skills are placed where Codex and
Claude Code can discover them. It does not fork or rewrite upstream prompts to
hide harness-specific behavioral differences. In particular, upstream reports
that `diagnosing-bugs` can trigger too eagerly in Codex; it remains an explicit
member of both profiles by design.

## Commands

`setup` installs global instructions and reconciles skills. `skills` and
`instructions` operate on only one component:

```bash
# profile is required; scope defaults to user and Agent defaults to both
./scripts/install-agent-setup.sh setup --profile personal

# all four profile/scope combinations are supported
./scripts/install-agent-setup.sh skills --profile work --scope user
./scripts/install-agent-setup.sh skills --profile personal --scope project

# project defaults to the current Git repository; an explicit path is optional
./scripts/install-agent-setup.sh skills \
  --profile work \
  --scope project \
  --project /path/to/repository \
  --agent claude

# component-only instruction update
./scripts/install-agent-setup.sh instructions --agent codex

# no network or destination writes
./scripts/install-agent-setup.sh setup --profile personal --dry-run

# use an existing managed checkout without fetching
./scripts/install-agent-setup.sh skills --profile personal --offline
```

Project scope affects skills only. Even when `setup --scope project` is used,
the shared instructions still go to the selected Agent's user-global path.

## Safety and ownership

Profiles are reconciled as exact desired state. Installing `work` over a
previous `personal` installation removes personal-only entries, but only when
the installer can prove ownership:

- a symlink resolves inside the managed upstream checkout; or
- a Git Bash copy contains the installer's provider-and-skill marker.

Unknown files, directories, and links are never overwritten. When project
scope finds the exact same managed skill at user scope, it reuses that entry
instead of creating a duplicate project entry. The last profile selected for a
given Agent and scope wins.

Instruction writes are content-aware. Equal content is left untouched. A
different regular file is backed up before replacement. Symlinks and other
non-regular targets are rejected. Codex users are warned when a global
`AGENTS.override.md` masks the installed `AGENTS.md`.

All Agent destinations are preflighted before installation begins. The
installer does not promise rollback for unexpected failures after writes have
started, but detectable conflicts fail before any destination is changed.

## Source and update behavior

The default source is an unmodified managed checkout of
`https://github.com/mattpocock/skills.git` at `main`. A normal run fetches the
requested ref. `--offline` requires an existing checkout and performs no
network access. `--dry-run` neither fetches nor writes; without an existing
checkout it reports the unverified plan.

Scheduled updates remain Linux-only and user-scope-only. The systemd user timer
records the selected profile and Agent target, updates skills only, and warns
when a manual installation disagrees with its active configuration. Project
scope, macOS, and Windows are updated by rerunning the installer manually.
Because the service records the installer's absolute path, re-enable the timer
after moving this repository.

```bash
./scripts/install-agent-setup.sh auto-update enable \
  --profile personal \
  --agent both
./scripts/install-agent-setup.sh auto-update status
./scripts/install-agent-setup.sh auto-update disable
```

## Compatibility

The previous installers remain as thin wrappers:

- `install-global-agent-charter.sh` preserves preview-by-default and `--apply`.
- `install-matt-pocock-skills.sh work` maps to work/user/Codex.
- `install-matt-pocock-skills.sh personal --project ...` maps to
  personal/project/Codex.

Existing legacy systemd timers continue to call the wrapper. Enabling the new
timer disables the legacy timer to avoid duplicate updates.

## Deliberate non-goals

- Native Windows PowerShell support.
- macOS launchd or Windows Task Scheduler integration.
- Per-Agent forks of third-party skill instructions.
- A general uninstall command.
