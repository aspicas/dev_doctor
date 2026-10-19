# Changelog

Every release has a section here. The release workflow publishes the
section matching the tag as the GitHub release notes, and the test suite
fails if `DEV_VERSION` in `bin/dev` has no section, so the version and
its notes cannot drift apart.

## 1.1.0

- New `ai` section in the manifest, with Claude Code (`claude-code`).
- Release process: tagged releases, this changelog, and CI that runs
  `just check` on macOS and Linux.

## 1.0.0

- First version: `dev doctor`, `dev install`, `dev update`, `dev setup`,
  `dev sections`, `dev tools`, `dev versions` and `dev manifest lint`,
  driven by `toolchain.yaml`.
- Remote bootstrap (`curl | bash`) and local installer.
