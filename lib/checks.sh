#!/usr/bin/env bash
# ============================================================
# Check engine.
# ============================================================
#
# Three kinds of check, in increasing order of usefulness:
#
#   existence    is the tool present at all
#   version      is the present tool the version we declared
#   integration  is the present tool actually wired into the shell,
#                into git, into the editor
#
# Existence and version are fully data driven and need no code per
# tool. Integration is inherently behavioural, so the manifest only
# names an integration id and the implementation lives in doctor/*.sh
# as `integration::<id with dots replaced by underscores>`.
# ============================================================

# ------------------------------------------------------------
# Remediation planning
# ------------------------------------------------------------

# Translate an install directive into a runnable command.
# Prints nothing when the provider cannot be automated.
fix::command_for() {
    local directive="$1"
    local provider="${directive%%:*}"
    local package="${directive#*:}"

    [ "$package" = "$directive" ] && package=""

    case "$provider" in
        brew)      printf 'brew install %s\n' "$package" ;;
        brew-cask) printf 'brew install --cask %s\n' "$package" ;;
        mise)      printf 'mise use --global %s@%s\n' "$package" "${2:-latest}" ;;
        *)         return 1 ;;
    esac
}

# Human guidance for the providers we refuse to automate.
fix::advice_for() {
    local directive="$1"
    local provider="${directive%%:*}"

    case "$provider" in
        xcode)  printf 'install Xcode from the App Store, then run xcode-select --install\n' ;;
        script) printf 'run the official install script for this tool\n' ;;
        system) printf 'provided by the operating system\n' ;;
        manual) printf 'install manually, no automated path is declared\n' ;;
        *)      printf 'no install directive declared for %s\n' "$PLATFORM_OS" ;;
    esac
}

# Queue remediation for the currently loaded tool.
# $1 optional version to pin when the provider is mise.
fix::plan_install() {
    local directive command
    directive="$(manifest::install_directive)"

    if [ -z "$directive" ]; then
        return 0
    fi

    if command="$(fix::command_for "$directive" "${1:-latest}")"; then
        report::fix "$M_name" "$command" safe
    else
        report::fix "$M_name" "$(fix::advice_for "$directive")" manual
    fi
}

# ------------------------------------------------------------
# Detection
# ------------------------------------------------------------

# True when the currently loaded tool is present on this machine.
# A binary in PATH wins; detect.path is the fallback for tools that
# are applications or checkouts rather than commands.
# Shared with `dev install`, which must agree with `dev doctor` about
# what "already installed" means.
check::present() {
    local expanded

    if [ -n "$M_binary" ] && have "$M_binary"; then
        return 0
    fi

    if [ -n "$M_detect_path" ]; then
        expanded="$(path::expand "$M_detect_path")"
        [ -e "$expanded" ] && return 0
    fi

    return 1
}

check::_report_missing() {
    case "$M_requirement" in
        required)
            report::fail "$M_name" "not installed"
            fix::plan_install "${M_version_expected:-latest}"
            ;;
        recommended)
            report::warn "$M_name" "not installed"
            fix::plan_install "${M_version_expected:-latest}"
            ;;
        *)
            report::skip "$M_name" "not installed, optional"
            ;;
    esac
}

# ------------------------------------------------------------
# Tool check
# ------------------------------------------------------------

check::tool() {
    local index="$1"
    local actual=""

    manifest::tool_load "$index"

    # Tools that do not apply here are omitted entirely rather than
    # reported as skipped, so the report stays about this machine.
    platform::supported "$M_platforms" || return 0

    if ! check::present; then
        check::_report_missing
        return 0
    fi

    if [ -n "$M_binary" ] || [ -n "$M_version_command" ]; then
        actual="$(version::probe "$M_binary" "$M_version_command")"
    fi

    if [ -z "$M_version_expected" ]; then
        report::ok "$M_name" "${actual:-installed}"
        check::integrations
        return 0
    fi

    # A binary that answers no version question while a version is
    # pinned is its own kind of problem. macOS ships a /usr/bin/java
    # stub that exists but resolves to no runtime at all.
    if [ -z "$actual" ]; then
        report::warn "$M_name" "present, version not detected" "$M_version_expected"
        check::_plan_version_fix
        check::integrations
        return 0
    fi

    if version::satisfies "$M_version_expected" "$actual" "$M_version_strategy"; then
        report::ok "$M_name" "$actual"
    else
        report::warn "$M_name" "$actual" "$M_version_expected"
        check::_plan_version_fix
    fi

    check::integrations
}

# A version drift is only automatically fixable when a version manager
# owns the tool. Anything else is reported and left to a human.
check::_plan_version_fix() {
    if [ "$M_manager" = "mise" ]; then
        report::fix "$M_name" "mise use --global $M_name@$M_version_expected" safe
    else
        report::fix "$M_name" "upgrade $M_name to $M_version_expected" manual
    fi
}

# ------------------------------------------------------------
# Integration dispatch
# ------------------------------------------------------------

check::integrations() {
    local id function_name

    [ -z "$M_integrations" ] && return 0

    for id in $M_integrations; do
        function_name="integration::$(printf '%s' "$id" | tr '.-' '__')"

        if ! declare -f "$function_name" >/dev/null 2>&1; then
            dev::debug "no implementation for integration '$id'"
            continue
        fi

        "$function_name"
    done
}

# ------------------------------------------------------------
# Helpers shared by integration implementations
# ------------------------------------------------------------

integration::ok()   { report::ok "$1" "${2:-configured}"; }
integration::warn() { report::warn "$1" "${2:-not configured}"; }
integration::fail() { report::fail "$1" "${2:-missing}"; }
