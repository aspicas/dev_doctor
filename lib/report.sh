#!/usr/bin/env bash
# ============================================================
# Reporting engine.
# ============================================================
#
# Every check funnels through `report::emit`, which appends a record to
# a results file and, in human mode, prints the line immediately so the
# report streams as it runs.
#
# Counters are derived from the results file at the end rather than
# incremented in place. That removes an entire class of bug where a
# check executed inside a subshell silently loses its tally.
# ============================================================

REPORT_RESULTS=""
REPORT_FIXES=""
REPORT_FORMAT="human"
REPORT_SECTION=""
REPORT_SECTION_PENDING=""
REPORT_NAME_WIDTH=28
REPORT_QUIET=""

report::init() {
    REPORT_RESULTS="$DEV_RUN_DIR/results.tsv"
    REPORT_FIXES="$DEV_RUN_DIR/fixes.tsv"
    : > "$REPORT_RESULTS"
    : > "$REPORT_FIXES"
}

# Whether the per-check lines are printed as they happen. Views that only
# render a digest at the end, such as `dev doctor --manual`, run every check
# but suppress the running commentary. The results file is written either
# way, so counters and exit status are unaffected.
report::streaming() {
    [ "$REPORT_FORMAT" = "human" ] && [ -z "$REPORT_QUIET" ]
}

# Pad to a column width measured in characters. printf field widths
# count bytes, and check names contain multibyte arrows, so using
# "%-*s" directly would misalign every row that contains one.
report::pad() {
    local text="$1"
    local width="$2"
    local pad=$((width - ${#text}))

    [ "$pad" -lt 1 ] && pad=1
    printf '%s%*s' "$text" "$pad" ""
}

report::header() {
    report::streaming || return 0
    printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
    printf '%s%s%s\n' "$C_DIM" "$(report::_rule "$1")" "$C_RESET"
}

# The braces around $out are required, not stylistic: bash 3.2 folds the
# following multibyte character into the variable name without them.
report::_rule() {
    local width="$1"
    local out=""

    case "$width" in
        *[!0-9]*) width=${#1} ;;
    esac

    while [ "$width" -gt 0 ]; do
        out="${out}─"
        width=$((width - 1))
    done

    printf '%s' "$out"
}

# Section titles are printed lazily so that sections without applicable
# tools, such as mobile toolchains on Linux, leave no empty heading.
report::section() {
    REPORT_SECTION="$1"
    REPORT_SECTION_PENDING="$1"
}

report::_flush_section() {
    [ -z "$REPORT_SECTION_PENDING" ] && return 0
    [ "$REPORT_FORMAT" = "human" ] && report::header "$REPORT_SECTION_PENDING"
    REPORT_SECTION_PENDING=""
    return 0
}

# report::emit STATUS NAME VALUE [EXPECTED]
#   STATUS is ok, warn, fail or skip.
#   VALUE  is the installed version or a short explanation.
report::emit() {
    local status="$1"
    local name="$2"
    local value="${3:-}"
    local expected="${4:-}"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$REPORT_SECTION" "$name" "$value" "$expected" \
        >> "$REPORT_RESULTS"

    report::streaming || return 0

    report::_flush_section

    local symbol color
    case "$status" in
        ok)   symbol="$SYM_OK";   color="$C_GREEN" ;;
        warn) symbol="$SYM_WARN"; color="$C_YELLOW" ;;
        fail) symbol="$SYM_FAIL"; color="$C_RED" ;;
        *)    symbol="$SYM_SKIP"; color="$C_DIM" ;;
    esac

    printf '  %s%s%s %s%s' \
        "$color" "$symbol" "$C_RESET" "$(report::pad "$name" "$REPORT_NAME_WIDTH")" "$value"

    if [ -n "$expected" ]; then
        printf ' %sexpected %s%s' "$C_DIM" "$expected" "$C_RESET"
    fi

    printf '\n'
}

report::ok()   { report::emit ok "$1" "${2:-}" "${3:-}"; }
report::warn() { report::emit warn "$1" "${2:-}" "${3:-}"; }
report::fail() { report::emit fail "$1" "${2:-}" "${3:-}"; }
report::skip() { report::emit skip "$1" "${2:-}" "${3:-}"; }

# ------------------------------------------------------------
# Remediation queue
# ------------------------------------------------------------
#
# RISK is either `safe`, meaning `dev doctor --fix` may run the command
# without further thought, or `manual`, meaning the command is only ever
# printed as advice. Anything touching credentials, signing keys or tool
# removal must be `manual`.

report::fix() {
    local label="$1"
    local command="$2"
    local risk="${3:-safe}"

    printf '%s\t%s\t%s\n' "$risk" "$label" "$command" >> "$REPORT_FIXES"
}

report::has_fixes() {
    [ -s "$REPORT_FIXES" ]
}

report::count() {
    local status="$1"
    awk -F'\t' -v s="$status" '$1 == s { n++ } END { print n + 0 }' "$REPORT_RESULTS"
}

# ------------------------------------------------------------
# Summary and exit status
# ------------------------------------------------------------

report::summary() {
    report::streaming || return 0

    local passed warnings failures skipped
    passed="$(report::count ok)"
    warnings="$(report::count warn)"
    failures="$(report::count fail)"
    skipped="$(report::count skip)"

    printf '\n%s%s%s\n' "$C_DIM" "$(report::_rule 46)" "$C_RESET"
    printf '%s%s%s passed   ' "$C_GREEN" "$passed" "$C_RESET"
    printf '%s%s%s warnings   ' "$C_YELLOW" "$warnings" "$C_RESET"
    printf '%s%s%s failures   ' "$C_RED" "$failures" "$C_RESET"
    printf '%s%s skipped%s\n' "$C_DIM" "$skipped" "$C_RESET"
}

# 0 clean, 1 warnings only, 2 failures present.
report::exit_status() {
    [ "$(report::count fail)" -gt 0 ] && return 2
    [ "$(report::count warn)" -gt 0 ] && return 1
    return 0
}

# ------------------------------------------------------------
# Machine readable rendering
# ------------------------------------------------------------

report::render_json() {
    awk -F'\t' '
        function esc(s) {
            gsub(/\\/, "\\\\", s)
            gsub(/"/, "\\\"", s)
            gsub(/\t/, " ", s)
            return s
        }
        BEGIN { print "{"; print "  \"checks\": [" }
        {
            counts[$1]++
            if (n++) print "    },"
            print "    {"
            printf "      \"status\": \"%s\",\n", esc($1)
            printf "      \"section\": \"%s\",\n", esc($2)
            printf "      \"name\": \"%s\",\n", esc($3)
            printf "      \"value\": \"%s\",\n", esc($4)
            printf "      \"expected\": \"%s\"\n", esc($5)
        }
        END {
            if (n) print "    }"
            print "  ],"
            print "  \"summary\": {"
            printf "    \"passed\": %d,\n", counts["ok"] + 0
            printf "    \"warnings\": %d,\n", counts["warn"] + 0
            printf "    \"failures\": %d,\n", counts["fail"] + 0
            printf "    \"skipped\": %d\n", counts["skip"] + 0
            print "  }"
            print "}"
        }
    ' "$REPORT_RESULTS"
}
