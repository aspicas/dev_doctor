# Task runner for dev doctor.
# The manifest declares `just` as the project task runner, so this
# project uses it too.

default:
    @just --list

# Run the test suite.
test:
    ./tests/run.sh

# Validate the manifest against the supported schema.
lint-manifest:
    ./bin/dev manifest lint

# Static analysis of every shell script, when shellcheck is available.
lint-shell:
    #!/usr/bin/env bash
    set -uo pipefail
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "shellcheck is not installed: brew install shellcheck"
        exit 1
    fi
    shellcheck --severity=warning --shell=bash --external-sources \
        bin/dev install.sh tests/run.sh lib/*.sh doctor/*.sh commands/*.sh

# Everything a change should pass before it lands.
check: lint-manifest lint-shell test

# Report on this machine.
doctor:
    ./bin/dev doctor

# Regenerate the Brewfile from the manifest.
brewfile:
    ./bin/dev install --write-brewfile
