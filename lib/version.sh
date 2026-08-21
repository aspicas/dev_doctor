#!/usr/bin/env bash
# ============================================================
# Version discovery and comparison.
# ============================================================
#
# Three comparison strategies are supported:
#
#   prefix   (default) the declared version pins a prefix. Declaring
#            "22" accepts 22.18.0 but rejects 23.x, and declaring "1.23"
#            rejects 1.24. This matches how a pinned toolchain behaves.
#   minimum  the installed version must be greater or equal.
#   exact    the versions must match component for component.
# ============================================================

# Pull the first version-looking token out of arbitrary tool output.
# The first token is used on purpose: build metadata and architecture
# strings usually trail the real version.
version::extract() {
    printf '%s\n' "$1" | head -n 1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -n 1
}

# Resolve the installed version of a tool.
# $1 binary, $2 optional shell pipeline overriding the default probe.
version::probe() {
    local binary="$1"
    local pipeline="${2:-}"
    local raw

    if [ -n "$pipeline" ]; then
        raw="$(run::pipeline "$pipeline")"
    else
        [ -z "$binary" ] && return 1
        raw="$(run::pipeline "$binary --version 2>&1")"
    fi

    [ -z "$raw" ] && return 1

    version::extract "$raw"
}

# Compare two dotted versions. Prints -1, 0 or 1.
version::compare() {
    local left="$1" right="$2"
    local saved="$IFS"
    local count index l r
    local lc rc

    IFS='.'
    # shellcheck disable=SC2162
    read -a lc <<< "$left"
    # shellcheck disable=SC2162
    read -a rc <<< "$right"
    IFS="$saved"

    count=${#lc[@]}
    [ ${#rc[@]} -gt "$count" ] && count=${#rc[@]}

    index=0
    while [ "$index" -lt "$count" ]; do
        l="${lc[$index]:-0}"
        r="${rc[$index]:-0}"
        case "$l" in *[!0-9]*|"") l=0 ;; esac
        case "$r" in *[!0-9]*|"") r=0 ;; esac

        if [ "$l" -gt "$r" ]; then printf '1\n'; return 0; fi
        if [ "$l" -lt "$r" ]; then printf -- '-1\n'; return 0; fi

        index=$((index + 1))
    done

    printf '0\n'
}

# True when `actual` satisfies `expected` under the given strategy.
version::satisfies() {
    local expected="$1"
    local actual="$2"
    local strategy="${3:-prefix}"
    local saved="$IFS"
    local index l r
    local ec ac

    [ -z "$expected" ] && return 0
    [ -z "$actual" ] && return 1

    case "$strategy" in
        minimum)
            [ "$(version::compare "$actual" "$expected")" -ge 0 ]
            return $?
            ;;
        exact)
            [ "$(version::compare "$actual" "$expected")" -eq 0 ]
            return $?
            ;;
    esac

    IFS='.'
    # shellcheck disable=SC2162
    read -a ec <<< "$expected"
    # shellcheck disable=SC2162
    read -a ac <<< "$actual"
    IFS="$saved"

    index=0
    while [ "$index" -lt "${#ec[@]}" ]; do
        l="${ec[$index]:-0}"
        r="${ac[$index]:-0}"
        case "$l" in *[!0-9]*|"") l=0 ;; esac
        case "$r" in *[!0-9]*|"") r=0 ;; esac
        [ "$l" -ne "$r" ] && return 1
        index=$((index + 1))
    done

    return 0
}
