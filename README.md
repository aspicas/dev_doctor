# dev doctor

A diagnostic and provisioning tool for a terminal-first development
workstation. It reads a single declarative manifest, discovers what is
actually installed and configured, and reports the difference.

```text
                       toolchain.yaml
                             │
                 ┌───────────┴───────────┐
                 ▼                       ▼
            dev install              dev doctor
                 │                       │
                 ▼                       ▼
             installs                 verifies
                                         │
                                    ✓  ⚠  ✗
```

One file describes the environment. Both commands read it, so the thing
that installs your tools and the thing that verifies them can never
disagree.

## Install

### One line (remote bootstrap)

```bash
curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash
```

The bootstrap script clones the repository to `~/.local/share/dev-doctor`, then
runs the local installer inside that checkout. It only fetches the project and
delegates to `./install.sh`; it does not duplicate install logic. The
confirmation prompt is read from `/dev/tty` rather than stdin, so it still
works when the script arrives through a pipe.

Running it again fetches the pinned ref and moves the checkout onto it, so the
same command both installs and updates. If `dev` is already linked from a
different checkout the install stops and asks for `--force`, rather than
quietly repointing a command you installed by hand.

Options go after `bash -s --`:

```bash
# Non-interactive, no prompt
curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash -s -- --yes

# Preview the plan, change nothing
curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash -s -- --dry-run

# Replace a `dev` already linked from another checkout
curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash -s -- --force

# Remove the symlink, the PATH entry and the checkout
curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash -s -- --uninstall --yes
```

The repository, the ref and the install locations also read environment
variables, which are easier to spot at the front of a one-liner than a flag
buried after `bash -s --`:

```bash
# Pin a tag or branch instead of main
DEV_DOCTOR_REF=v1.0.0 \
  curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash

# Install a fork or a private mirror
DEV_DOCTOR_REPO=https://github.com/you/dev_doctor.git \
  curl -fsSL https://raw.githubusercontent.com/you/dev_doctor/main/scripts/bootstrap.sh | bash
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `DEV_DOCTOR_REPO` | `https://github.com/aspicas/dev_doctor.git` | repository to clone |
| `DEV_DOCTOR_DIR` | `~/.local/share/dev-doctor` | where the checkout lives |
| `DEV_DOCTOR_REF` | `main` | branch or tag to install |
| `PREFIX` | `~/.local/bin` | where `dev` is linked |

Run `--help` to see the full option list:

```bash
curl -fsSL https://raw.githubusercontent.com/aspicas/dev_doctor/main/scripts/bootstrap.sh | bash -s -- --help
```

### From a checkout

```bash
git clone https://github.com/aspicas/dev_doctor.git ~/Projects/dev_doctor
cd ~/Projects/dev_doctor
./install.sh
```

Or use the bootstrap in local mode, which skips cloning:

```bash
./scripts/bootstrap.sh --local --yes
```

This validates the manifest, links `bin/dev` into `~/.local/bin`, and adds
that directory to your `PATH` in `.zshrc`.

```bash
./install.sh --prefix /usr/local/bin   # link somewhere else
./install.sh --force                   # replace an existing dev
./install.sh --yes                     # non-interactive uninstall/remove-data
./install.sh --no-path                 # do not touch the shell config
./install.sh --uninstall               # remove the link and the PATH entry
./install.sh --uninstall --remove-data # also delete this checkout
```

Requires `bash` 3.2, POSIX `awk`, and `git` for the remote bootstrap.
Both `bash` and `awk` already exist on macOS and Linux.

### What it writes to your shell config

The `PATH` export goes into `$ZDOTDIR/.zshrc`, or `~/.config/zsh/.zshrc`,
or `~/.zshrc` — whichever applies to your setup, in that order. It is
written inside a marked block:

```zsh
# >>> dev doctor >>>
# Added by dev doctor. Remove with: ./install.sh --uninstall
export PATH="$HOME/.local/bin:$PATH"
# <<< dev doctor <<<
```

Nothing outside those markers is ever touched. Re-running the installer
rewrites the block rather than appending a second one, so changing
`--prefix` updates the entry instead of leaving a stale one behind, and
`--uninstall` removes it and leaves the file as it was. The first time the
file is modified it is copied to `<file>.pre-dev-doctor`.

`$HOME` is kept symbolic rather than expanded so the line survives being
committed to a dotfiles repository and applied on another machine.

Two things worth knowing:

- zsh only reads `.zshrc` for **interactive** shells. `dev` will resolve in
  your terminal but not in a non-interactive `zsh -c` script. If you need
  it there, the export belongs in `.zshenv`.
- If chezmoi manages the target file, the installer says so and prints the
  source path instead of silently making a change that the next
  `chezmoi apply` would revert. Use `--no-path` and put the line in the
  chezmoi source.

## Use

```bash
dev doctor                    # full report
dev doctor --section git      # one section
dev doctor --deep             # include the slow checks
dev doctor --fix              # apply the fixes that are safe to automate
dev doctor --manual           # only the fixes that need a human
dev doctor --json             # machine readable, for CI

dev tools                     # what the manifest declares
dev versions                  # declared versions against installed ones
dev install                   # install what is declared and missing
dev update                    # update brew, mise and chezmoi
dev setup git-signing         # guided config for what doctor will not automate
dev manifest lint             # validate toolchain.yaml
```

Exit status is `0` when clean, `1` with warnings, `2` with failures, so it
drops straight into CI.

## What it checks

Existence alone is a weak signal, so there are three levels.

**Existence.** Is it there at all? Either a binary on `PATH` or, for
applications and checkouts, a path on disk.

```text
✓ ripgrep                     14.1.0
✗ gitleaks                    not installed
```

**Version.** Is it the version you declared? A pinned `1.23` accepts
`1.23.9` and rejects `1.24.0`. Comparison is numeric and component-wise, so
`1.10` is correctly newer than `1.9`.

```text
⚠ go                          1.24.5  expected 1.23
⚠ java                        present, version not detected  expected 21
```

That second line is a real macOS failure mode: `/usr/bin/java` exists as a
stub even with no JDK installed, so `command -v java` succeeds while
nothing works.

**Integration.** This is the interesting one. Having `mise` on disk says
nothing about whether your shell ever activates it.

```text
✓ mise                        2026.8.1
✓ mise → zsh                  initialised
✓ mise → health               healthy
⚠ direnv → mise               no bridge configured
⚠ git → commit signing        disabled
✓ xcode → command line tools  /Applications/Xcode.app/Contents/Developer
⚠ android → ANDROID_HOME      not set
```

A tool that is installed but not wired in is invisible to `command -v` and
is exactly the class of problem that costs an afternoon.

## What `--fix` will and will not do

`dev doctor` only ever reports. `dev doctor --fix` runs the subset of
remediations that are deterministic and reversible, and asks first.

Automated:

- installing a missing package with `brew` or `brew --cask`
- installing or pinning a runtime with `mise`
- cloning a plugin manager, syncing editor plugins, starting a container
  runtime

Never automated, only printed:

- SSH keys, agents and file permissions
- git commit signing
- secrets and credentials
- anything that removes a tool
- **any file that chezmoi owns**

`dev doctor --manual` prints that second list on its own, without the
report and without the automated fixes, which is useful once `--fix` has
done its part and only the human work is left. It runs the same checks, so
the exit status still reflects the state of the machine; only the output is
narrowed. It cannot be combined with `--fix`, since the two describe
opposite halves of the same list.

That last one is a design decision, not caution for its own sake. The
manifest names chezmoi as the source of truth for dotfiles. If `--fix`
appended `eval "$(mise activate zsh)"` to your deployed `~/.zshrc`, the
next `chezmoi apply` would silently revert it, and you would have created
exactly the drift this tool exists to detect. So shell and git
configuration are reported with the precise line to add, and you put it in
the chezmoi source where it belongs.

Anything in that second category that still deserves a guided path gets an
explicit command:

```bash
dev setup git-signing
```

## Layout

```text
dev_doctor/
├── toolchain.yaml          the manifest, single source of truth
├── Brewfile                generated from the manifest, never hand written
├── install.sh              local installer, run from a checkout
├── scripts/
│   └── bootstrap.sh        remote one-line installer (curl | bash)
├── justfile
│
├── bin/
│   └── dev                 dispatcher
│
├── lib/
│   ├── manifest.awk        YAML subset parser, zero dependencies
│   ├── manifest.sh         load, query and validate
│   ├── checks.sh           existence, version and integration engine
│   ├── core.sh             paths, styling, timeouts, temp state
│   ├── platform.sh         os detection
│   ├── report.sh           output, counters, remediation queue
│   └── version.sh          extraction and comparison
│
├── doctor/                 integration checks, one module per domain
│   ├── shell.sh
│   ├── environment.sh
│   ├── git.sh
│   ├── editor.sh
│   ├── containers.sh
│   ├── security.sh
│   └── mobile.sh
│
├── commands/               one file per `dev` subcommand
│   ├── doctor.sh
│   ├── install.sh
│   ├── tools.sh
│   ├── setup.sh
│   └── manifest.sh
│
├── docs/
│   ├── manifest-schema.md
│   └── environment.reference.yaml
│
└── tests/
    └── run.sh
```

## Adding a tool

Edit `toolchain.yaml`:

```yaml
  - name: watchexec
    binary: watchexec
    section: automation
    requirement: recommended
    platforms: [macos, linux]
    install:
      macos: brew:watchexec
      linux: brew:watchexec
    doc: Run commands on file change
```

Then `dev manifest lint`. No shell code changes, and `dev install`,
`dev doctor`, `dev tools` and the `Brewfile` all pick it up at once.

Full field reference in [docs/manifest-schema.md](docs/manifest-schema.md).

## Design notes

**Why a built-in YAML parser instead of `yq`.** This tool has to work on a
machine that is broken or brand new. A doctor that cannot run until you
install a dependency has the dependency arrow pointing the wrong way. The
parser needs only `bash` and POSIX `awk`.

The cost is a restricted grammar, which is why `dev manifest lint` exists
and why the parser emits explicit errors instead of guessing. A field that
is silently ignored produces a report that is confidently wrong, which is
worse than a report that refuses to run.

**Why bash 3.2.** It is the interpreter macOS ships. Targeting anything
newer would mean the tool cannot diagnose a machine until that machine has
already been fixed. No associative arrays, no `readarray`; the manifest is
flattened once into a tab-separated cache and queried with `awk`.

**Why counters are derived, not incremented.** Every check writes a record
to a results file and the totals are computed from it at the end. A check
that ran inside a subshell and lost its tally is a bug that only shows up
as a wrong number at the bottom of a long report, which is exactly the kind
of bug nobody notices.

**Why `set -e` is not used.** A diagnostic tool runs commands that are
expected to fail. Aborting on the first non-zero status would make the
design fragile at its core.

**Why integrations are code and data is data.** "Is ripgrep installed" is a
fact and belongs in YAML. "Is fzf actually bound into your zsh keymap" is a
behaviour. Expressing the second one declaratively means inventing a small
programming language inside a config file, so integrations are named in the
manifest and implemented as shell functions in `doctor/`.

## Tests

```bash
./tests/run.sh
```

45 assertions covering the parser (including the pipelines, commas and
quoted strings that break naive implementations), the linter's ability to
reject a bad manifest, and version extraction against real-world output
from go, node, java, tmux, neovim and docker.

## The reference document

`docs/environment.reference.yaml` is the original descriptive document:
philosophy, aliases, project standards, maintenance policy. It is prose for
humans and is intentionally not executable. `toolchain.yaml` is the part a
machine can act on. Keeping them apart is what stops the manifest from
drifting into documentation nobody runs.
