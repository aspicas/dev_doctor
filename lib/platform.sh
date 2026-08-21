#!/usr/bin/env bash
# ============================================================
# Platform detection.
# ============================================================
#
# Platform ids match the `platforms` field in the manifest so that a
# tool declaration can be filtered without any translation layer.
# ============================================================

PLATFORM_OS=""
PLATFORM_ARCH=""

platform::init() {
    case "$(uname -s)" in
        Darwin) PLATFORM_OS="macos" ;;
        Linux) PLATFORM_OS="linux" ;;
        *) PLATFORM_OS="unknown" ;;
    esac

    PLATFORM_ARCH="$(uname -m)"
}

platform::is_macos() { [ "$PLATFORM_OS" = "macos" ]; }
platform::is_linux() { [ "$PLATFORM_OS" = "linux" ]; }

# True when a space separated platform list includes the current platform.
# An empty list means the entry applies everywhere.
platform::supported() {
    local list="$1"
    local entry

    [ -z "$list" ] && return 0

    for entry in $list; do
        [ "$entry" = "$PLATFORM_OS" ] && return 0
    done

    return 1
}

platform::describe() {
    printf '%s %s\n' "$PLATFORM_OS" "$PLATFORM_ARCH"
}
