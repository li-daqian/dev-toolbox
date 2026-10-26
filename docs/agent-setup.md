# Personal Agent Setup

`scripts/install-agent-setup.sh` is the public installer for this repository's
personal Agent environment. It manages one global instruction template and a
reviewed subset of the upstream `mattpocock/skills` repository, plus the
`last30days` skill from `mvanhorn/last30days-skill` in both profiles.

## Design model

Skill selection and installation location are independent dimensions:

| Dimension | Values | Meaning |
| --- | --- | --- |
| Profile | `personal`, `work` | Selects the exact desired skill manifest |
| Scope | `user`, `project` | Selects a user-wide or Git-project destination |
| Agent target | `codex`, `claude`, `both` | Selects which supported Agent receives the installation |

The `personal` manifest contains the explicitly reviewed upstream promoted
`engineering` and `productivity` skills. The smaller `work` manifest contains
11 skills: `grilling`, `grill-me`, `grill-with-docs`, `diagnosing-bugs`, `codebase-design`,
`domain-modeling`, `improve-codebase-architecture`, `handoff`, `teach`,
`writing-for-agents`, and `to-questionnaire`. All eleven are also in `personal`.
`domain-modeling` supports the domain-document updates used by architecture
discussions. New upstream skills never enter a profile merely because a
directory appeared upstream.

Both profiles preserve upstream invocation policies. `codebase-design`,
`domain-modeling`, and `writing-for-agents` allow implicit invocation, as do the
existing `grilling` and `diagnosing-bugs`. The other six work-profile skills,
including `grill-with-docs`, require explicit invocation. The installer does
not patch skill metadata.

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

last30days uses a separate checkout at
`~/.local/share/codex-skill-sources/last30days-skill` (under `$XDG_DATA_HOME`
when configured). Its complete `skills/last30days` directory is linked or
copied, including engine scripts and references. Provider-specific ownership
markers keep it separate from mattpocock reconciliation. Both sources are
preflighted before Agent destinations are changed.

Use `--last30days-ref`, `--last30days-source-root`, or
`--last30days-source-dir` to override its ref, managed checkout, or read-only
external checkout independently of the mattpocock source options. The environment
variable `AGENT_SETUP_LAST30DAYS_SOURCE_DIR` also supplies an external checkout.
`--offline` and `--dry-run` apply to both sources. Scheduled updates serialize
both managed sources and refs; external source overrides are rejected.

The research engine requires Python 3.12+. Installation does not run research,
read browser cookies, provision optional tools, or configure API keys. Invoke
`$last30days` in Codex to start the upstream setup/research workflow. Additional
sources may need credentials or tools; installation alone does not enable them.

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
