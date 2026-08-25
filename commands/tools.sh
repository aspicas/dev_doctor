#!/usr/bin/env bash
# ============================================================
# `dev tools`     — what the manifest declares.
# `dev versions`  — declared versions against installed versions.
# `dev sections`  — the section ids `--section` accepts.
# ============================================================

tools::usage() {
    cat <<'USAGE'
Usage: dev tools [--section <id>] [--requirement <level>]

List everything declared in toolchain.yaml for this platform.

The values accepted by --section are the ids printed by `dev sections`.
USAGE
}

tools::main() {
    local only_section="" only_requirement=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --section) shift; only_section="${1:-}" ;;
            --requirement) shift; only_requirement="${1:-}" ;;
            -h|--help) tools::usage; return 0 ;;
            *) dev::error "unknown option: $1"; return 64 ;;
        esac
        shift
    done

    style::init auto
    manifest::load

    if [ -n "$only_section" ]; then
        manifest::require_section "$only_section" || return 64
    fi

    local section title index directive

    for section in $(manifest::section_ids); do
        [ -n "$only_section" ] && [ "$section" != "$only_section" ] && continue

        title="$(manifest::section_title "$section")"
        local printed_header=0

        for index in $(manifest::tool_indices_in_section "$section"); do
            manifest::tool_load "$index"
            platform::supported "$M_platforms" || continue
            [ -n "$only_requirement" ] && [ "$M_requirement" != "$only_requirement" ] && continue

            if [ "$printed_header" -eq 0 ]; then
                printf '\n%s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
                printed_header=1
            fi

            directive="$(manifest::install_directive)"
            printf '  %-18s %-14s %-22s %s\n' \
                "$M_name" "$M_requirement" "${directive:-—}" "$C_DIM$M_doc$C_RESET"
        done
    done

    printf '\n'
}

# ------------------------------------------------------------

sections::usage() {
    cat <<'USAGE'
Usage: dev sections

List the section ids declared in toolchain.yaml. These are the values
accepted by --section on doctor, tools and install.
USAGE
}

sections::main() {
    if [ $# -gt 0 ]; then
        case "$1" in
            -h|--help) sections::usage; return 0 ;;
            *) dev::error "unknown option: $1"; sections::usage >&2; return 64 ;;
        esac
    fi

    style::init auto
    manifest::load

    local section title index count

    printf '\n%s%-20s %-28s %s%s\n' \
        "$C_BOLD" "ID" "TITLE" "TOOLS" "$C_RESET"

    for section in $(manifest::section_ids); do
        title="$(manifest::section_title "$section")"
        [ -n "$title" ] || title="$section"

        count=0
        for index in $(manifest::tool_indices_in_section "$section"); do
            count=$((count + 1))
        done

        printf '%-20s %-28s %d\n' "$section" "$title" "$count"
    done

    printf '\n%sUse `dev doctor --section <id>` to restrict a report.%s\n\n' \
        "$C_DIM" "$C_RESET"
}

# ------------------------------------------------------------

versions::usage() {
    cat <<'USAGE'
Usage: dev versions

Show the declared version next to the installed version for every tool
that pins one.
USAGE
}

versions::main() {
    if [ $# -gt 0 ]; then
        case "$1" in
            -h|--help) versions::usage; return 0 ;;
            *) dev::error "unknown option: $1"; versions::usage >&2; return 64 ;;
        esac
    fi

    style::init auto
    manifest::load

    local index actual status color

    printf '\n%s%-18s %-12s %-12s %s%s\n' \
        "$C_BOLD" "TOOL" "EXPECTED" "INSTALLED" "MANAGER" "$C_RESET"

    for index in $(manifest::tool_indices); do
        manifest::tool_load "$index"
        platform::supported "$M_platforms" || continue
        [ -z "$M_version_expected" ] && continue

        actual="$(version::probe "$M_binary" "$M_version_command")"

        if [ -z "$actual" ]; then
            status="missing"
            color="$C_RED"
        elif version::satisfies "$M_version_expected" "$actual" "$M_version_strategy"; then
            status="$actual"
            color="$C_GREEN"
        else
            status="$actual"
            color="$C_YELLOW"
        fi

        printf '%-18s %-12s %s%-12s%s %s\n' \
            "$M_name" "$M_version_expected" "$color" "$status" "$C_RESET" "${M_manager:-—}"
    done

    printf '\n'
}
