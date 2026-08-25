#!/usr/bin/env bash
# ============================================================
# Installer for dev doctor.
# ============================================================
#
# Run it from a checkout:
#
#   ./install.sh
#
# For a one-line remote install, use scripts/bootstrap.sh instead:
#
#   curl -fsSL <bootstrap-url> | bash
#
# All it does is verify the prerequisites, validate the manifest and
# link `bin/dev` onto your PATH. Nothing is downloaded from this script.
# ============================================================

set -uo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
FORCE=""
VERIFY=1
UNINSTALL=""
CONFIGURE_PATH=1
ASSUME_YES=""
REMOVE_DATA=""

SOURCE_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""

# The PATH export is written between markers so that it can be updated
# in place or removed cleanly. Nothing outside the block is ever touched.
MARK_BEGIN="# >>> dev doctor >>>"
MARK_END="# <<< dev doctor <<<"

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
Usage: ./install.sh [options]

Options:
  --prefix <dir>     where to link the `dev` command, default ~/.local/bin
  --force            replace an existing `dev` at the target
  --yes, -y          do not prompt when removing data
  --no-path          do not touch the zsh configuration
  --no-verify        skip the manifest validation step
  --uninstall        remove the symlink and the PATH entry
  --remove-data      with --uninstall, also delete this checkout
  -h, --help         show this help
USAGE
}

confirm() {
    local prompt="$1"
    local reply=""

    [ -n "$ASSUME_YES" ] && return 0

    # When the remote bootstrap invokes this script, stdin is still the pipe
    # curl is writing into, so the prompt has to go to the controlling
    # terminal instead. /dev/tty exists as a device node even when no terminal
    # is attached, so the only reliable probe is to open it. With no terminal
    # at all, refuse rather than assume consent.
    if { : >/dev/tty && : </dev/tty; } 2>/dev/null; then
        printf '%s [y/N] ' "$prompt" >/dev/tty
        read -r reply </dev/tty || reply=""
    elif [ -t 0 ]; then
        printf '%s [y/N] ' "$prompt"
        read -r reply || reply=""
    else
        die "$prompt (re-run with --yes in a non-interactive shell)"
    fi

    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) printf 'Nothing was changed.\n'; exit 0 ;;
    esac
}

# Only remove a checkout that looks like dev doctor, never an arbitrary path.
install::safe_to_remove_data() {
    [ -f "$SOURCE_ROOT/toolchain.yaml" ] || return 1
    [ -x "$SOURCE_ROOT/bin/dev" ] || return 1
    return 0
}

install::remove_data() {
    if ! install::safe_to_remove_data; then
        bad "refusing to delete $SOURCE_ROOT, it does not look like a dev doctor checkout"
        return 1
    fi

    confirm "Delete the checkout at $SOURCE_ROOT?"
    rm -rf "$SOURCE_ROOT" || return 1
    ok "removed $SOURCE_ROOT"
    return 0
}

# ------------------------------------------------------------
# Shell configuration
# ------------------------------------------------------------

# Prefer an explicit ZDOTDIR, then the XDG layout this environment
# declares, then the traditional location. Only the first hit is used,
# because writing the export twice would be worse than not writing it.
zsh_config_target() {
    if [ -n "${ZDOTDIR:-}" ]; then
        printf '%s\n' "$ZDOTDIR/.zshrc"
        return
    fi

    if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/.zshrc" ]; then
        printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/.zshrc"
        return
    fi

    printf '%s\n' "$HOME/.zshrc"
}

# Keep $HOME symbolic so the line survives being copied to another
# machine or committed to a dotfiles repository.
# shellcheck disable=SC2016
path_export_line() {
    case "$PREFIX" in
        "$HOME"/*) printf 'export PATH="$HOME/%s:$PATH"\n' "${PREFIX#"$HOME"/}" ;;
        *) printf 'export PATH="%s:$PATH"\n' "$PREFIX" ;;
    esac
}

has_block() {
    [ -f "$1" ] && grep -qF "$MARK_BEGIN" "$1" 2>/dev/null
}

remove_block() {
    local file="$1"
    local temporary

    [ -f "$file" ] || return 0

    temporary="$(mktemp "${TMPDIR:-/tmp}/dev-doctor-zshrc.XXXXXX")" || return 1

    awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
        $0 == begin { skip = 1; next }
        $0 == end   { skip = 0; next }
        !skip       { print }
    ' "$file" > "$temporary" || { rm -f "$temporary"; return 1; }

    cat "$temporary" > "$file" || { rm -f "$temporary"; return 1; }
    rm -f "$temporary"
}

append_block() {
    local file="$1"

    # Append to a file whose last line has no newline would otherwise
    # comment out the marker by joining it to existing content.
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
        printf '\n' >> "$file"
    fi

    {
        printf '%s\n' "$MARK_BEGIN"
        printf '# Added by dev doctor. Remove with: ./install.sh --uninstall\n'
        path_export_line
        printf '%s\n' "$MARK_END"
    } >> "$file"
}

# Warn when the target is generated by chezmoi. Editing the deployed copy
# would be reverted by the next `chezmoi apply`, which is exactly the
# drift `dev doctor` exists to report.
warn_if_chezmoi_managed() {
    local file="$1"
    local source_path

    command -v chezmoi >/dev/null 2>&1 || return 0

    source_path="$(chezmoi source-path "$file" 2>/dev/null)"
    [ -n "$source_path" ] || return 0

    warn "chezmoi manages this file"
    printf '\n    The next `chezmoi apply` will revert it. Add the same line to\n'
    printf '    the source instead:\n\n'
    printf '      %s\n' "$source_path"
}

# ------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) shift; PREFIX="${1:-}" ;;
        --force) FORCE=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --no-path) CONFIGURE_PATH="" ;;
        --no-verify) VERIFY="" ;;
        --uninstall) UNINSTALL=1 ;;
        --remove-data) REMOVE_DATA=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

[ -n "$PREFIX" ] || die "--prefix needs a directory"
TARGET="$PREFIX/dev"

printf '\n%sdev doctor%s\n' "$C_BOLD" "$C_RESET"
printf '%s%s%s\n' "$C_DIM" "$SOURCE_ROOT" "$C_RESET"

# ------------------------------------------------------------
# Uninstall
# ------------------------------------------------------------

if [ -n "$UNINSTALL" ]; then
    step "Uninstalling"

    if [ ! -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        warn "nothing linked at $TARGET"
    elif [ -L "$TARGET" ]; then
        rm -f "$TARGET" && ok "removed $TARGET"
    else
        bad "$TARGET is not a symlink, leaving it alone"
        exit 1
    fi

    zshrc="$(zsh_config_target)"
    if has_block "$zshrc"; then
        if remove_block "$zshrc"; then
            ok "removed the PATH entry from $zshrc"
        else
            bad "could not edit $zshrc"
        fi
    else
        ok "no PATH entry to remove"
    fi

    if [ -n "$REMOVE_DATA" ]; then
        install::remove_data || exit 1
    else
        printf '\n%sThe checkout at %s was kept.%s\n' "$C_DIM" "$SOURCE_ROOT" "$C_RESET"
        printf '%sRemove it with: ./install.sh --uninstall --remove-data%s\n' "$C_DIM" "$C_RESET"
    fi

    printf '\n%sOpen a new shell for the PATH change to take effect.%s\n\n' "$C_DIM" "$C_RESET"
    exit 0
fi

# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------

step "Checking prerequisites"

# bash 3.2 is the macOS system shell and the floor this project targets.
bash_major="${BASH_VERSINFO[0]:-0}"
bash_minor="${BASH_VERSINFO[1]:-0}"
if [ "$bash_major" -gt 3 ] || { [ "$bash_major" -eq 3 ] && [ "$bash_minor" -ge 2 ]; }; then
    ok "bash ${BASH_VERSION%%(*}"
else
    die "bash 3.2 or newer is required, found ${BASH_VERSION:-unknown}"
fi

if command -v awk >/dev/null 2>&1; then
    ok "awk $(command -v awk)"
else
    die "awk is required and was not found"
fi

for optional in git sed grep; do
    if command -v "$optional" >/dev/null 2>&1; then
        ok "$optional"
    else
        warn "$optional not found, some checks will be degraded"
    fi
done

case "$(uname -s)" in
    Darwin) ok "platform macos" ;;
    Linux) ok "platform linux" ;;
    *) warn "unrecognised platform $(uname -s), platform filters will not match" ;;
esac

# ------------------------------------------------------------
# Layout
# ------------------------------------------------------------

step "Checking the checkout"

for required in bin/dev lib/manifest.awk lib/core.sh toolchain.yaml; do
    if [ -e "$SOURCE_ROOT/$required" ]; then
        ok "$required"
    else
        die "missing $required, is this a complete checkout?"
    fi
done

chmod +x "$SOURCE_ROOT/bin/dev" 2>/dev/null

# ------------------------------------------------------------
# Manifest
# ------------------------------------------------------------

if [ -n "$VERIFY" ]; then
    step "Validating the manifest"

    if "$SOURCE_ROOT/bin/dev" manifest lint >/dev/null 2>&1; then
        ok "toolchain.yaml is valid"
    else
        printf '\n'
        "$SOURCE_ROOT/bin/dev" manifest lint
        die "the manifest is not valid, refusing to install"
    fi
fi

# ------------------------------------------------------------
# Link
# ------------------------------------------------------------

step "Linking the dev command"

if [ ! -d "$PREFIX" ]; then
    mkdir -p "$PREFIX" || die "could not create $PREFIX"
    ok "created $PREFIX"
fi

if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    existing="$(readlink "$TARGET" 2>/dev/null)"

    if [ "$existing" = "$SOURCE_ROOT/bin/dev" ]; then
        ok "already linked"
    elif [ -n "$FORCE" ]; then
        rm -f "$TARGET" || die "could not replace $TARGET"
        ln -s "$SOURCE_ROOT/bin/dev" "$TARGET" || die "could not link $TARGET"
        ok "replaced $TARGET"
    else
        bad "$TARGET already exists"
        printf '\n    it points at: %s\n' "${existing:-a regular file}"
        printf '    re-run with --force to replace it\n\n'
        exit 1
    fi
else
    ln -s "$SOURCE_ROOT/bin/dev" "$TARGET" || die "could not link $TARGET"
    ok "linked $TARGET"
fi

# ------------------------------------------------------------
# PATH
# ------------------------------------------------------------

step "Configuring PATH"

zshrc="$(zsh_config_target)"
needs_new_shell=""
path_failed=""

if [ -z "$CONFIGURE_PATH" ]; then
    ok "skipped, --no-path was given"
    case ":$PATH:" in
        *":$PREFIX:"*) ;;
        *)
            warn "$PREFIX is not on PATH, add this yourself:"
            printf '\n      %s\n' "$(path_export_line)"
            ;;
    esac
elif has_block "$zshrc"; then
    # Rewrite rather than skip, so that changing --prefix updates the
    # entry instead of leaving a stale one behind.
    if remove_block "$zshrc" && append_block "$zshrc"; then
        ok "updated the PATH entry in $zshrc"
        warn_if_chezmoi_managed "$zshrc"
    else
        bad "could not edit $zshrc"
        path_failed=1
    fi
else
    if [ ! -e "$zshrc" ]; then
        mkdir -p "$(dirname "$zshrc")" 2>/dev/null
        : > "$zshrc" && ok "created $zshrc"
    else
        # One backup, taken only the first time the file is modified.
        if [ ! -e "$zshrc.pre-dev-doctor" ]; then
            cp "$zshrc" "$zshrc.pre-dev-doctor" && ok "backed up to $zshrc.pre-dev-doctor"
        fi
    fi

    if append_block "$zshrc"; then
        ok "added $PREFIX to PATH in $zshrc"
        needs_new_shell=1
        warn_if_chezmoi_managed "$zshrc"
    else
        bad "could not write to $zshrc"
        path_failed=1
    fi
fi

case ":$PATH:" in
    *":$PREFIX:"*) ok "$PREFIX is already on PATH in this shell" ;;
    *) [ -z "$path_failed" ] && needs_new_shell=1 ;;
esac

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

if [ -n "$path_failed" ]; then
    printf '\n%sInstalled, but PATH was not configured.%s\n\n' "$C_YELLOW" "$C_RESET"
    printf '  The `dev` command is linked at %s but will not resolve\n' "$TARGET"
    printf '  until that directory is on PATH. Add this line yourself:\n\n'
    printf '      %s\n\n' "$(path_export_line)"
    exit 1
fi

printf '\n%sInstalled.%s\n\n' "$C_GREEN" "$C_RESET"

if [ -n "$needs_new_shell" ]; then
    printf '  %sStart a new shell, or run: source %s%s\n\n' \
        "$C_DIM" "$zshrc" "$C_RESET"
fi
printf '  dev doctor        see how far this machine has drifted\n'
printf '  dev doctor --fix  apply the fixes that are safe to automate\n'
printf '  dev update        refresh brew, mise, fvm and chezmoi\n'
printf '  dev sections      the ids `--section` accepts\n'
printf '  dev install       install what the manifest declares and you lack\n'
printf '  dev tools         list everything the manifest declares\n'
printf '  dev help          everything else\n\n'
