# Manifest schema

`toolchain.yaml` is parsed by `lib/manifest.awk`, which implements a
deliberately small subset of YAML. Anything outside that subset is a hard
error rather than a silent omission, because a field that is quietly
ignored produces a report that is confidently wrong.

Validate at any time with:

```bash
dev manifest lint
```

## Why not yq

`dev doctor` exists to diagnose a machine that may be broken or brand new.
Requiring a YAML processor to be installed before you can find out what is
missing inverts the dependency. The parser therefore needs nothing beyond
`bash` and POSIX `awk`, both of which are already present on any macOS or
Linux system.

The cost of that decision is a restricted grammar, which is why the linter
exists.

## Supported YAML

| Construct | Supported | Example |
|---|---|---|
| Top level scalar | yes | `version: 1` |
| Top level map, one level deep | yes | `meta:` then `  name: value` |
| Sequence of maps | yes | `tools:` then `  - name: rg` |
| Nested map inside an item | yes | `install:` then `  macos: brew:rg` |
| Inline flow sequence | yes | `platforms: [macos, linux]` |
| Block sequence of scalars | yes | `platforms:` then `  - macos` |
| Comments | yes | full line, or trailing after whitespace |
| Quoted scalars | yes | quotes are stripped |
| Anchors, aliases, multi-line scalars, nested sequences | no | rejected |

Indentation must be two spaces per level. Tabs are rejected.

Sequence values are joined with single spaces, so sequence entries must not
contain spaces. In practice they are always identifiers.

## Top level keys

| Key | Meaning |
|---|---|
| `version` | Schema version. Must be `1`. |
| `meta` | Environment name, supported platforms, Brewfile path. |
| `sections` | Report layout. Tools are grouped and printed in this order. |
| `tools` | The tools themselves. |

## Section entries

```yaml
sections:
  - id: cli
    title: Command line
```

## Tool entries

Only the keys below are accepted. Anything else fails linting.

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | Unique identifier and display name. |
| `binary` | see note | Command to look for in `PATH`. |
| `section` | yes | Must match a declared section `id`. |
| `category` | no | Free form taxonomy, for humans. |
| `requirement` | no | `required`, `recommended` or `optional`. Defaults to `recommended`. |
| `platforms` | no | Where the tool applies. Empty means everywhere. |
| `manager` | no | Which version manager owns it, for example `mise`. |
| `replaces` | no | The native tool it supersedes, documentation only. |
| `doc` | no | One line description. |
| `install.macos` | no | Install directive for macOS. |
| `install.linux` | no | Install directive for Linux. |
| `version.command` | no | Shell pipeline that prints the version. |
| `version.expected` | no | The declared version. |
| `version.strategy` | no | `prefix`, `minimum` or `exact`. Defaults to `prefix`. |
| `detect.path` | see note | Filesystem path proving the tool is present. |
| `integrations` | no | Integration check ids to run after detection. |

Note: a tool must declare `binary`, `detect.path`, or both. Something that
can be detected by neither is not a check, it is a comment.

### requirement

The requirement level decides what a missing tool means, which is the
difference between a report you read and a report you ignore.

| Level | Missing tool becomes |
|---|---|
| `required` | a failure, exit status 2 |
| `recommended` | a warning, exit status 1 |
| `optional` | a skipped line, exit status unaffected |

### install directives

Written as `provider:package`, or a bare provider when there is nothing to
name.

| Provider | Automatable | Command |
|---|---|---|
| `brew` | yes | `brew install <package>` |
| `brew-cask` | yes | `brew install --cask <package>` |
| `mise` | yes | `mise use --global <package>@<version>` |
| `xcode` | no | advice only |
| `script` | no | advice only |
| `manual` | no | advice only |
| `system` | no | advice only |

Only the automatable providers are ever executed by `dev doctor --fix`.

### version detection

Without `version.command`, the probe runs `<binary> --version 2>&1`. The
first version-shaped token on the first line is used, because build
metadata and architecture strings trail the real version:

```text
go version go1.23.0 darwin/arm64   ->  1.23.0
openjdk version "21.0.1" 2023-...  ->  21.0.1
```

When that heuristic does not fit, `version.command` takes an arbitrary
shell pipeline and the same extraction is applied to its output:

```yaml
version:
  command: lazygit --version | tr ',' '\n' | sed -n 's/.*version=//p'
```

There is one escape hatch rather than a second pattern-matching field, on
the grounds that a pipeline can already express anything a pattern could.

### version strategies

| Strategy | `expected` | Accepts | Rejects |
|---|---|---|---|
| `prefix` | `22` | `22.18.0` | `23.0.0` |
| `prefix` | `1.23` | `1.23.9` | `1.24.0` |
| `minimum` | `14.0` | `14.1.0` | `13.9` |
| `exact` | `14.1.0` | `14.1.0` | `14.1.1` |

Comparison is component-wise and numeric, so `1.10` is correctly newer
than `1.9`.

### integrations

An integration id names a shell function, with dots and dashes replaced by
underscores:

```yaml
integrations: [shell.zsh.mise, mise.health]
```

resolves to `integration::shell_zsh_mise` and `integration::mise_health`,
which live in `doctor/*.sh`. An id with no implementation is skipped
silently unless `DEV_DEBUG` is set.

Integrations are code rather than data on purpose. "Is mise installed" is a
fact about the filesystem and belongs in the manifest. "Is mise actually
activated by your shell" is a behaviour, and trying to express it
declaratively would mean inventing a small programming language inside
YAML.

## Adding a tool

```yaml
  - name: watchexec
    binary: watchexec
    section: automation
    category: automation.watch
    requirement: recommended
    platforms: [macos, linux]
    install:
      macos: brew:watchexec
      linux: brew:watchexec
    doc: Run commands on file change
```

Then:

```bash
dev manifest lint
dev doctor --section automation
```

No shell code changes. That is the point.
