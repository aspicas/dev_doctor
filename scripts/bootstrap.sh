#!/usr/bin/env bash
# ============================================================
# Remote bootstrap for dev doctor.
# ============================================================
#
# Intended entry point for one-line installs:
#
#   curl -fsSL https://raw.githubusercontent.com/OWNER/dev_doctor/main/scripts/bootstrap.sh | bash
#
# This script is separate from ./install.sh on purpose. It only downloads
# or updates the checkout, then delegates to the local installer inside
# that checkout. The local installer never executes remote code by itself.
#
# Override defaults with environment variables:
#
#   DEV_DOCTOR_REPO   git URL, default below
#   DEV_DOCTOR_DIR    checkout location, default ~/.local/share/dev-doctor
#   DEV_DOCTOR_REF    branch or tag, default main
#   PREFIX            where to link `dev`, default ~/.local/bin
#
# Pass arguments after the pipe:
#
#   curl ... | bash -s -- --uninstall
#   curl ... | bash -s -- --dry-run
# ============================================================

set -uo pipefail

# Set this when you publish the repository.
DEV_DOCTOR_REPO="${DEV_DOCTOR_REPO:-https://github.com/davidgarcia/dev_doctor.git}"
DEV_DOCTOR_DIR="${DEV_DOCTOR_DIR:-$HOME/.local/share/dev-doctor}"
DEV_DOCTOR_REF="${DEV_DOCTOR_REF:-main}"
PREFIX="${PREFIX:-$HOME/.local/bin}"

DRY_RUN=""
UNINSTALL=""
FORCE=""
CONFIGURE_PATH=1
ASSUME_YES=""
LOCAL=""

# ------------------------------------------------------------
# Output
# ------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
else
    C_RESET=""; C_DIM=""; C_BOLD=""
    C_GREEN=""; C_YELLOW=""; C_RED=""
fi

ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1"; }
step() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
die()  { printf '\n%serror%s %s\n\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Usage: curl -fsSL <bootstrap-url> | bash [ -s -- [options] ]

Options:
  --prefix <dir>     where to link `dev`, default ~/.local/bin
  --dir <path>       checkout location, default ~/.local/share/dev-doctor
  --ref <branch>     branch or tag to install, default main
  --repo <url>       git repository URL
  --force            replace an existing `dev` symlink
  --no-path          do not touch the zsh configuration
  --yes, -y          do not prompt
  --dry-run          print the plan and change nothing
  --local            use this repository instead of cloning
  --uninstall        remove the symlink, PATH entry and checkout
  -h, --help         show this help

Environment:
  DEV_DOCTOR_REPO    git URL
  DEV_DOCTOR_DIR     checkout location
  DEV_DOCTOR_REF     branch or tag
  PREFIX             link directory
USAGE
}

run() {
    if [ -n "$DRY_RUN" ]; then
        printf '  %s→%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    "$@"
}

confirm() {
    local prompt="$1"
    local reply

    [ -n "$ASSUME_YES" ] && return 0
    [ -n "$DRY_RUN" ] && return 0

    if [ ! -t 0 ]; then
        die "$prompt (re-run with --yes in a non-interactive shell)"
    fi

    printf '%s [y/N] ' "$prompt"
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) printf 'Nothing was changed.\n'; exit 0 ;;
    esac
}

bootstrap::safe_to_remove_dir() {
    [ -f "$1/toolchain.yaml" ] || return 1
    [ -x "$1/bin/dev" ] || return 1
    return 0
}

bootstrap::uninstall_fallback() {
    local target="$PREFIX/dev"
    local link

    if [ -L "$target" ]; then
        link="$(readlink "$target")"
        case "$link" in
            "$DEV_DOCTOR_DIR"/*|"$HOME/.local/share/dev-doctor"/*)
                run rm -f "$target" && ok "removed $target"
                ;;
            *)
                warn "$target points elsewhere, leaving it alone"
                ;;
        esac
    fi

    if [ -d "$DEV_DOCTOR_DIR" ]; then
        if bootstrap::safe_to_remove_dir "$DEV_DOCTOR_DIR"; then
            confirm "Delete the checkout at $DEV_DOCTOR_DIR?"
            run rm -rf "$DEV_DOCTOR_DIR" && ok "removed $DEV_DOCTOR_DIR"
        else
            warn "$DEV_DOCTOR_DIR does not look like a dev doctor checkout"
        fi
    fi
}

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) shift; PREFIX="${1:-}" ;;
        --dir) shift; DEV_DOCTOR_DIR="${1:-}" ;;
        --ref) shift; DEV_DOCTOR_REF="${1:-}" ;;
        --repo) shift; DEV_DOCTOR_REPO="${1:-}" ;;
        --force) FORCE=1 ;;
        --no-path) CONFIGURE_PATH="" ;;
        --yes|-y) ASSUME_YES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --local) LOCAL=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

[ -n "$PREFIX" ] || die "--prefix needs a directory"
[ -n "$DEV_DOCTOR_DIR" ] || die "--dir needs a directory"

if [ -n "$LOCAL" ]; then
    DEV_DOCTOR_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    [ -n "$DEV_DOCTOR_REPO" ] || die "DEV_DOCTOR_REPO is not set"
fi

printf '\n%sdev doctor bootstrap%s\n' "$C_BOLD" "$C_RESET"
printf '%s%s @ %s%s\n' "$C_DIM" "$DEV_DOCTOR_REF" "$DEV_DOCTOR_DIR" "$C_RESET"

# ------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------

if [ -n "$UNINSTALL" ]; then
    step "Uninstalling"

    if [ -x "$DEV_DOCTOR_DIR/install.sh" ]; then
        run "$DEV_DOCTOR_DIR/install.sh" \
            --prefix "$PREFIX" \
            --uninstall \
            --remove-data \
            ${ASSUME_YES:+--yes}
    else
        warn "no installer at $DEV_DOCTOR_DIR/install.sh"
        bootstrap::uninstall_fallback
    fi

    printf '\n%sDone.%s\n\n' "$C_DIM" "$C_RESET"
    exit 0
fi

# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------

step "Checking prerequisites"

command -v bash >/dev/null 2>&1 || die "bash is required"
ok "bash"

if [ -z "$LOCAL" ]; then
    command -v git >/dev/null 2>&1 || die "git is required to fetch the checkout"
    ok "git"
fi

# ------------------------------------------------------------
# Fetch checkout
# ------------------------------------------------------------

if [ -n "$LOCAL" ]; then
    step "Using local checkout"
    ok "$DEV_DOCTOR_DIR"
else
    step "Fetching the checkout"

    if [ -d "$DEV_DOCTOR_DIR/.git" ]; then
        ok "existing checkout at $DEV_DOCTOR_DIR"
        if [ -n "$DRY_RUN" ]; then
            run git -C "$DEV_DOCTOR_DIR" fetch --depth 1 origin "$DEV_DOCTOR_REF"
            run git -C "$DEV_DOCTOR_DIR" checkout "$DEV_DOCTOR_REF"
        else
            git -C "$DEV_DOCTOR_DIR" fetch --depth 1 origin "$DEV_DOCTOR_REF" \
                || die "could not fetch $DEV_DOCTOR_REF from $DEV_DOCTOR_REPO"
            git -C "$DEV_DOCTOR_DIR" checkout "$DEV_DOCTOR_REF" \
                || die "could not checkout $DEV_DOCTOR_REF"
        fi
        ok "updated to $DEV_DOCTOR_REF"
    elif [ -d "$DEV_DOCTOR_DIR" ]; then
        die "$DEV_DOCTOR_DIR exists but is not a git checkout"
    else
        if [ -n "$DRY_RUN" ]; then
            run mkdir -p "$(dirname "$DEV_DOCTOR_DIR")"
            run git clone --depth 1 --branch "$DEV_DOCTOR_REF" "$DEV_DOCTOR_REPO" "$DEV_DOCTOR_DIR"
        else
            mkdir -p "$(dirname "$DEV_DOCTOR_DIR")" \
                || die "could not create $(dirname "$DEV_DOCTOR_DIR")"
            git clone --depth 1 --branch "$DEV_DOCTOR_REF" "$DEV_DOCTOR_REPO" "$DEV_DOCTOR_DIR" \
                || die "could not clone $DEV_DOCTOR_REPO"
        fi
        ok "cloned to $DEV_DOCTOR_DIR"
    fi
fi

if [ -n "$DRY_RUN" ]; then
    printf '\n%sDry run complete. Nothing was changed.%s\n\n' "$C_DIM" "$C_RESET"
    exit 0
fi

[ -x "$DEV_DOCTOR_DIR/install.sh" ] || die "checkout is missing install.sh"

# ------------------------------------------------------------
# Local install
# ------------------------------------------------------------

step "Running the local installer"

confirm "Install dev doctor from $DEV_DOCTOR_DIR?"

install_args=(--prefix "$PREFIX")
[ -n "$FORCE" ] && install_args+=(--force)
[ -n "$ASSUME_YES" ] && install_args+=(--yes)
[ -z "$CONFIGURE_PATH" ] && install_args+=(--no-path)

exec "$DEV_DOCTOR_DIR/install.sh" "${install_args[@]}"
