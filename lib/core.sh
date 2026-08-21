#!/usr/bin/env bash
# ============================================================
# Core runtime: paths, terminal styling and process helpers.
# ============================================================
#
# Targets bash 3.2 because that is the interpreter shipped with macOS.
# No associative arrays, no `readarray`, no `${var,,}`.
#
# `set -e` is deliberately NOT used. A diagnostic tool runs commands that
# are expected to fail, and aborting on the first non zero status would
# make the whole design fragile.
# ============================================================

set -uo pipefail

DEV_ROOT="${DEV_ROOT:-}"
if [ -z "$DEV_ROOT" ]; then
    echo "core.sh: DEV_ROOT must be set before sourcing" >&2
    exit 1
fi

DEV_LIB_DIR="$DEV_ROOT/lib"
DEV_DOCTOR_DIR="$DEV_ROOT/doctor"
DEV_COMMANDS_DIR="$DEV_ROOT/commands"
DEV_MANIFEST="${DEV_MANIFEST:-$DEV_ROOT/toolchain.yaml}"

# ------------------------------------------------------------
# Styling
# ------------------------------------------------------------

SYM_OK="✓"
SYM_WARN="⚠"
SYM_FAIL="✗"
SYM_SKIP="·"

C_RESET=""
C_DIM=""
C_BOLD=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_BLUE=""

style::init() {
    local force="${1:-auto}"

    if [ "$force" = "never" ]; then return 0; fi
    if [ "$force" = "auto" ]; then
        if [ -n "${NO_COLOR:-}" ]; then return 0; fi
        if [ ! -t 1 ]; then return 0; fi
    fi

    C_RESET=$'\033[0m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_BLUE=$'\033[34m'
}

# ------------------------------------------------------------
# Diagnostics for the tool itself, not for the environment
# ------------------------------------------------------------

dev::log() { printf '%s\n' "$*" >&2; }
dev::debug() { [ -n "${DEV_DEBUG:-}" ] && printf '%sdebug%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; return 0; }
dev::warn() { printf '%swarning%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
dev::error() { printf '%serror%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }

dev::die() {
    dev::error "$*"
    exit 1
}

# ------------------------------------------------------------
# Process helpers
# ------------------------------------------------------------

# True when a command exists in PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# Expand a leading ~ without invoking eval on manifest supplied data.
# The tildes below are case patterns matching a literal character, which
# is exactly what a manifest path contains.
# shellcheck disable=SC2088
path::expand() {
    case "$1" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# Run a command with a wall clock limit so that a hung binary cannot
# freeze the whole report. Falls back to a plain run when the platform
# has no usable timeout implementation.
run::limited() {
    local seconds="$1"
    shift

    if have timeout; then
        timeout "$seconds" "$@" 2>/dev/null
        return $?
    fi
    if have gtimeout; then
        gtimeout "$seconds" "$@" 2>/dev/null
        return $?
    fi

    "$@" 2>/dev/null
}

# Evaluate a manifest supplied shell pipeline with a time limit.
# The manifest is trusted local configuration, in the same way a
# Makefile or justfile is trusted.
run::pipeline() {
    local pipeline="$1"
    local seconds="${2:-$DEV_COMMAND_TIMEOUT}"

    run::limited "$seconds" /bin/sh -c "$pipeline"
}

DEV_COMMAND_TIMEOUT="${DEV_COMMAND_TIMEOUT:-10}"

# ------------------------------------------------------------
# Temporary state
# ------------------------------------------------------------

DEV_RUN_DIR=""

state::init() {
    DEV_RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dev-doctor.XXXXXX")" ||
        dev::die "unable to create a temporary directory"
    trap 'state::cleanup' EXIT INT TERM
}

state::cleanup() {
    [ -n "$DEV_RUN_DIR" ] && [ -d "$DEV_RUN_DIR" ] && rm -rf "$DEV_RUN_DIR"
    return 0
}
