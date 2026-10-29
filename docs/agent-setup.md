# Personal Agent Setup

`scripts/install-agent-setup.sh` manages the global instruction template for
Codex and Claude Code. Skill installation and updates use upstream marketplaces.

## Global instructions

```bash
# Both commands install instructions only; default Agent target is both
./scripts/install-agent-setup.sh setup
./scripts/install-agent-setup.sh instructions --agent codex
./scripts/install-agent-setup.sh setup --dry-run
./scripts/install-agent-setup.sh instructions --stdout
```

Destinations:

- Codex: `${CODEX_HOME:-~/.codex}/AGENTS.md`
- Claude Code: `${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md`

Use `--codex-path` or `--claude-path` to override a destination. Instructions
always install at user scope. The old profile, skill scope/source, offline,
and auto-update options have been removed.

The installer supports Bash on Linux, macOS, WSL, and Windows Git Bash.
Native PowerShell is not supported.

Instruction writes are content-aware. Equal content is left untouched; changed
regular files are backed up. Symlinks and non-regular instruction targets are
rejected. Codex users are warned if `AGENTS.override.md` masks `AGENTS.md`.
Both Agent destinations are preflighted before installation begins; unexpected
failures after writes begin do not have automatic rollback.

`install-global-agent-charter.sh` remains a wrapper with preview by default and
`--apply` to install instructions.

## Skills via Codex marketplaces

Install skills separately from global instructions:

```bash
codex plugin marketplace add mattpocock/skills
codex plugin add mattpocock-skills@mattpocock

codex plugin marketplace add mvanhorn/last30days-skill
codex plugin add last30days@last30days-skill
```

The repository no longer manages third-party skill checkouts, symlinks, copies,
removal scripts, or systemd update units. These Codex commands do not install
skills into Claude Code; use the upstream Claude Code installation instructions
when needed. Avoid activating both a legacy skill copy and its plugin.

last30days runtime dependencies, including Python 3.12+, Node.js and `yt-dlp`,
are separate from plugin installation. Prepare them according to upstream
instructions and ensure they are on the Agent's PATH. Additional data sources
may require credentials or optional tools configured through the upstream setup
workflow. Migrating the skill does not require deleting research configuration,
saved results, or existing runtime tools.

Verify Codex installation with:

```bash
codex plugin list --marketplace mattpocock --json
codex plugin list --marketplace last30days-skill --json
```

Confirm `installed` and `enabled` are true. For a runtime check, invoke
`$last30days` in a new Codex session and request a source health check; source
availability still depends on configured tools and credentials.
