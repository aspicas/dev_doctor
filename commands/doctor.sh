#!/usr/bin/env bash
# ============================================================
# `dev doctor` — compare the declared toolchain against reality.
# ============================================================

DOCTOR_DEEP=""
DOCTOR_APPLY=""
DOCTOR_ASSUME_YES=""
DOCTOR_ONLY_SECTION=""
DOCTOR_MANUAL_ONLY=""

doctor::usage() {
    cat <<'USAGE'
Usage: dev doctor [options]

Compare toolchain.yaml against what is actually installed and configured.

Options:
  --fix              apply the fixes classified as safe, after confirmation
  --manual           print only the fixes that cannot be automated
  --yes              do not prompt when applying fixes
  --deep             include slow checks such as flutter doctor and brew bundle
  --section <id>     restrict the report to a single section
  --format <fmt>     human (default) or json
  --no-color         disable colour output
  -h, --help         show this help

Exit status:
  0  no problems
  1  warnings only
  2  at least one failure
USAGE
}

doctor::main() {
    local color="auto"

    while [ $# -gt 0 ]; do
        case "$1" in
            --fix) DOCTOR_APPLY=1 ;;
            --manual) DOCTOR_MANUAL_ONLY=1 ;;
            --yes|-y) DOCTOR_ASSUME_YES=1 ;;
            --deep) DOCTOR_DEEP=1 ;;
            --section) shift; DOCTOR_ONLY_SECTION="${1:-}" ;;
            --format) shift; REPORT_FORMAT="${1:-human}" ;;
            --json) REPORT_FORMAT="json" ;;
            --no-color) color="never" ;;
            -h|--help) doctor::usage; return 0 ;;
            *) dev::error "unknown option: $1"; doctor::usage >&2; return 64 ;;
        esac
        shift
    done

    case "$REPORT_FORMAT" in
        human|json) ;;
        *) dev::die "unsupported format: $REPORT_FORMAT" ;;
    esac

    if [ -n "$DOCTOR_MANUAL_ONLY" ]; then
        # The manual list is by definition what --fix cannot do, so asking
        # for both is a contradiction rather than a narrowing.
        if [ -n "$DOCTOR_APPLY" ]; then
            dev::die "--manual and --fix are mutually exclusive"
        fi
        if [ "$REPORT_FORMAT" != "human" ]; then
            dev::die "--manual is only available in the human format"
        fi
        REPORT_QUIET=1
    fi

    [ "$REPORT_FORMAT" = "json" ] && color="never"
    style::init "$color"

    manifest::load
    manifest::lint || dev::die "refusing to run against an invalid manifest"
    report::init

    doctor::intro
    doctor::run_sections

    if [ -n "$DOCTOR_MANUAL_ONLY" ]; then
        doctor::report_manual
    else
        report::summary
        doctor::report_fixes
    fi

    if [ "$REPORT_FORMAT" = "json" ]; then
        report::render_json
    fi

    report::exit_status
}

doctor::intro() {
    report::streaming || return 0

    printf '\n%sDeveloper Environment Doctor%s\n' "$C_BOLD" "$C_RESET"
    printf '%s%s · %s%s\n' \
        "$C_DIM" "$(manifest::meta meta.name)" "$(platform::describe)" "$C_RESET"
}

doctor::run_sections() {
    local section title index

    # Validated up front. Checking afterwards would confuse an unknown
    # section with a valid one that has no applicable tools here, such as
    # the mobile section on Linux.
    if [ -n "$DOCTOR_ONLY_SECTION" ]; then
        if ! manifest::section_ids | grep -qx "$DOCTOR_ONLY_SECTION"; then
            dev::error "unknown section: $DOCTOR_ONLY_SECTION"
            dev::log "available: $(manifest::section_ids | tr '\n' ' ')"
            exit 64
        fi
    fi

    for section in $(manifest::section_ids); do
        if [ -n "$DOCTOR_ONLY_SECTION" ] && [ "$section" != "$DOCTOR_ONLY_SECTION" ]; then
            continue
        fi

        title="$(manifest::section_title "$section")"
        [ -n "$title" ] || title="$section"
        report::section "$title"

        for index in $(manifest::tool_indices_in_section "$section"); do
            check::tool "$index"
        done
    done
}

# ------------------------------------------------------------
# Remediation
# ------------------------------------------------------------

doctor::report_fixes() {
    [ "$REPORT_FORMAT" != "human" ] && return 0
    report::has_fixes || return 0

    local risk label command seen=""
    local safe_count=0

    printf '\n%sSuggested fixes%s\n' "$C_BOLD" "$C_RESET"
    printf '%s──────────────%s\n' "$C_DIM" "$C_RESET"

    while IFS=$'\t' read -r risk label command; do
        [ -z "$risk" ] && continue
        case "$seen" in *"|$command|"*) continue ;; esac
        seen="$seen|$command|"

        if [ "$risk" = "safe" ]; then
            safe_count=$((safe_count + 1))
            printf '  %s\n' "$command"
        fi
    done < "$REPORT_FIXES"

    doctor::print_manual_fixes

    printf '\n'

    if [ "$safe_count" -eq 0 ]; then
        return 0
    fi

    if [ -z "$DOCTOR_APPLY" ]; then
        printf '%sRun `dev doctor --fix` to apply the %d safe fix(es).%s\n' \
            "$C_DIM" "$safe_count" "$C_RESET"
        return 0
    fi

    doctor::apply_fixes "$safe_count"
}

# Printed both on its own by `--manual` and as the tail of the full report.
# Returns non-zero when there was nothing to print, so that callers can say
# so instead of emitting a bare heading.
doctor::print_manual_fixes() {
    local risk label command seen="" printed=0

    while IFS=$'\t' read -r risk label command; do
        [ -z "$risk" ] && continue
        [ "$risk" = "safe" ] && continue
        case "$seen" in *"|$command|"*) continue ;; esac
        seen="$seen|$command|"

        if [ "$printed" -eq 0 ]; then
            printf '\n%sNeeds a human%s\n' "$C_BOLD" "$C_RESET"
            printf '%s────────────%s\n' "$C_DIM" "$C_RESET"
            printed=1
        fi
        printf '  %s%s%s%s\n' "$C_DIM" "$(report::pad "$label" 26)" "$C_RESET" "$command"
    done < "$REPORT_FIXES"

    [ "$printed" -eq 1 ]
}

doctor::report_manual() {
    if doctor::print_manual_fixes; then
        printf '\n'
    else
        printf '\n%sNothing needs a human.%s\n\n' "$C_GREEN" "$C_RESET"
    fi
}

doctor::apply_fixes() {
    local expected="$1"
    local risk label command seen=""
    local commands=()
    local reply

    while IFS=$'\t' read -r risk label command; do
        [ "$risk" = "safe" ] || continue
        case "$seen" in *"|$command|"*) continue ;; esac
        seen="$seen|$command|"
        commands+=("$command")
    done < "$REPORT_FIXES"

    [ "${#commands[@]}" -eq 0 ] && return 0

    if [ -z "$DOCTOR_ASSUME_YES" ]; then
        if [ ! -t 0 ]; then
            dev::error "--fix needs a terminal to confirm, or pass --yes"
            return 1
        fi
        printf 'Apply %d fix(es)? [y/N] ' "$expected"
        read -r reply
        case "$reply" in
            y|Y|yes|YES) ;;
            *) printf 'Nothing was changed.\n'; return 0 ;;
        esac
    fi

    local failures=0
    for command in "${commands[@]}"; do
        printf '\n%s→ %s%s\n' "$C_BLUE" "$command" "$C_RESET"
        if /bin/sh -c "$command"; then
            printf '%s%s done%s\n' "$C_GREEN" "$SYM_OK" "$C_RESET"
        else
            printf '%s%s failed%s\n' "$C_RED" "$SYM_FAIL" "$C_RESET"
            failures=$((failures + 1))
        fi
    done

    printf '\n%sRe-run `dev doctor` to confirm.%s\n' "$C_DIM" "$C_RESET"
    [ "$failures" -gt 0 ] && return 1
    return 0
}
