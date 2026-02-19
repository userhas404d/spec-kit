# Worktrunk Migration (v0.2.0)

## Summary

This release replaces traditional `git checkout -b` branching with [Worktrunk](https://worktrunk.dev) (`wt`) for worktree-based feature development and removes all PowerShell scripts in favor of a bash-only, cross-platform approach.

## Why Worktrunk?

Spec Kit's feature workflow creates numbered branches (`001-feature-name`, `002-another-feature`) for each specification. Worktrunk improves this by giving each feature its own **isolated worktree** instead of switching branches in a single working directory:

- **Parallel work**: Multiple features can be open simultaneously in separate directories
- **No stash juggling**: Switching features doesn't require stashing or committing in-progress work
- **Cross-platform**: `wt` is a single Rust binary — no shell-specific scripts needed
- **Clean integration**: `wt switch --create` is a drop-in replacement for `git checkout -b`

## Why Remove PowerShell?

With Worktrunk handling cross-platform concerns as a compiled Rust binary, maintaining duplicate PowerShell scripts became unnecessary overhead:

- **Worktrunk runs everywhere**: macOS, Linux, Windows (no shell dependency)
- **Windows users**: Run bash scripts via Git Bash (bundled with Git for Windows) or WSL
- **Reduced maintenance**: One set of scripts instead of two, with no feature drift between shell variants

## What Changed

### Branching

| Before                         | After                            |
| ------------------------------ | -------------------------------- |
| `git checkout -b 001-feature`  | `wt switch --create 001-feature` |
| Single working directory       | Isolated worktree per feature    |
| `git fetch --all --prune` scan | Removed (unnecessary with `wt`)  |

### Scripts

| Action               | Before                             | After                                 |
| -------------------- | ---------------------------------- | ------------------------------------- |
| Create feature       | `create-new-feature.sh` / `.ps1`   | `create-new-feature.sh` (bash only)   |
| Common helpers       | `common.sh` / `common.ps1`         | `common.sh` + new `has_wt()` function |
| Setup plan           | `setup-plan.sh` / `.ps1`           | `setup-plan.sh` (bash only)           |
| Check prerequisites  | `check-prerequisites.sh` / `.ps1`  | `check-prerequisites.sh` (bash only)  |
| Update agent context | `update-agent-context.sh` / `.ps1` | `update-agent-context.sh` (bash only) |

### CLI (`specify`)

| Change                     | Detail                                                            |
| -------------------------- | ----------------------------------------------------------------- |
| `--script` option removed  | No longer needed (always `sh`)                                    |
| Script type picker removed | Interactive selection of `sh`/`ps` eliminated from `specify init` |
| `wt` check added           | `specify check` now reports Worktrunk availability                |
| `wt` required              | `specify init` errors and exits if `wt` is not installed          |

### Command Templates

All 8 command templates (`specify.md`, `plan.md`, `implement.md`, `clarify.md`, `tasks.md`, `taskstoissues.md`, `analyze.md`, `checklist.md`) had their `ps:` frontmatter entries removed. Only `sh:` script references remain.

### Documentation

- **README.md**: Worktrunk added to prerequisites, recommended hooks section added, "branch created" updated to "worktree created"
- **CONTRIBUTING.md**: Worktrunk added to prerequisites, `git checkout -b` replaced with `wt switch --create`
- **AGENTS.md**: New "Branching Strategy" section documenting the Worktrunk workflow

## Breaking Changes

1. **PowerShell scripts removed** — Windows users must use Git Bash or WSL
2. **`--script` CLI option removed** — `specify init` no longer accepts `--script sh`/`--script ps`

## Installation

```bash
# Install Worktrunk
brew install worktrunk

# Enable shell integration
wt config shell install
```

See [worktrunk.dev](https://worktrunk.dev) for other installation methods.

## Project Hooks

`specify init` now ships a default `.config/wt.toml` that opens VS Code when a new worktree is created:

```toml
[post-create]
vscode = "code {{ worktree_path }}"
```

> **Note:** The default configuration assumes VS Code as the IDE. If you use a different editor, update the `post-create` hook command accordingly (e.g., `cursor {{ worktree_path }}` for Cursor, `zed {{ worktree_path }}` for Zed).

You can extend `.config/wt.toml` with additional hooks to suit your project's needs. See [worktrunk.dev/hook](https://worktrunk.dev/hook/) for full documentation.
