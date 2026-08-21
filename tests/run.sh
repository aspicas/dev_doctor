#!/usr/bin/env bash
# ============================================================
# Test suite.
# ============================================================
#
# Run with: ./tests/run.sh
#
# The parser and the version comparison are the two places where a
# quiet mistake would make the whole report confidently wrong, so they
# carry the bulk of the coverage.
# ============================================================

set -uo pipefail

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ROOT="$(cd -P "$TESTS_DIR/.." && pwd)"
export DEV_ROOT

FIXTURES="$TESTS_DIR/fixtures"

. "$DEV_ROOT/lib/core.sh"
. "$DEV_ROOT/lib/platform.sh"
. "$DEV_ROOT/lib/version.sh"
. "$DEV_ROOT/lib/report.sh"
. "$DEV_ROOT/lib/manifest.sh"

TESTS_RUN=0
TESTS_FAILED=0
CURRENT_GROUP=""

group() {
    CURRENT_GROUP="$1"
    printf '\n%s\n' "$1"
}

assert_eq() {
    local expected="$1" actual="$2" what="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        printf '  ok    %s\n' "$what"
        return 0
    fi

    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  FAIL  %s\n' "$what"
    printf '        expected: [%s]\n' "$expected"
    printf '        actual:   [%s]\n' "$actual"
}

assert_status() {
    local expected="$1" actual="$2" what="$3"
    assert_eq "$expected" "$actual" "$what"
}

# ------------------------------------------------------------

parse() {
    awk -f "$DEV_ROOT/lib/manifest.awk" "$1" 2>/dev/null
}

field() {
    local file="$1" item="$2" key="$3"
    parse "$file" | awk -F'\t' -v i="$item" -v k="$key" \
        '$1 == "TOOL" && $2 == i && $3 == k { print $4; exit }'
}

# ------------------------------------------------------------
group "parser: scalars, nested maps and sequences"

assert_eq "ripgrep" "$(field "$FIXTURES/valid.yaml" 1 name)" "reads a scalar"
assert_eq "brew:ripgrep" "$(field "$FIXTURES/valid.yaml" 1 install.macos)" "flattens a nested map"
assert_eq "macos linux" "$(field "$FIXTURES/valid.yaml" 1 platforms)" "joins a flow sequence"
assert_eq "macos linux" "$(field "$FIXTURES/valid.yaml" 2 platforms)" "joins a block sequence"
assert_eq "14" "$(field "$FIXTURES/valid.yaml" 1 version.expected)" "strips quotes"
assert_eq "shell.zsh.fzf git.delta" "$(field "$FIXTURES/valid.yaml" 1 integrations)" "keeps dotted ids"

group "parser: values that break naive implementations"

assert_eq "rg --version | head -n 1" \
    "$(field "$FIXTURES/valid.yaml" 1 version.command)" "preserves a shell pipeline"
assert_eq "Fast, recursive search" \
    "$(field "$FIXTURES/valid.yaml" 1 doc)" "drops a trailing comment but keeps a comma"
# shellcheck disable=SC2088  # the literal tilde is the point of the assertion
assert_eq "~/.local/share/zinit/zinit.git" \
    "$(field "$FIXTURES/valid.yaml" 2 detect.path)" "leaves tilde expansion to the caller"

group "parser: malformed input is rejected, not guessed"

parse_output="$(awk -f "$DEV_ROOT/lib/manifest.awk" "$FIXTURES/malformed.yaml" 2>/dev/null)"
assert_status "3" "$?" "exits non zero on bad indentation"
assert_eq "1" "$(printf '%s\n' "$parse_output" | grep -c '^ERROR')" "reports the offending line"

group "manifest: validation catches declaration mistakes"

state::init
DEV_MANIFEST="$FIXTURES/broken.yaml"
manifest::load
lint_errors="$(manifest::lint 2>&1 >/dev/null)"
lint_status=$?

assert_status "1" "$lint_status" "lint fails on an invalid manifest"

for expectation in "unknown section" "invalid requirement" "unknown install provider" "unknown key" "duplicate tool name" "neither a binary nor detect.path"; do
    if printf '%s\n' "$lint_errors" | grep -qi "$expectation"; then
        assert_eq "found" "found" "reports: $expectation"
    else
        assert_eq "found" "missing" "reports: $expectation"
    fi
done

group "manifest: the real toolchain is valid"

DEV_MANIFEST="$DEV_ROOT/toolchain.yaml"
manifest::load
manifest::lint >/dev/null 2>&1
assert_status "0" "$?" "toolchain.yaml passes lint"
assert_eq "1" "$(manifest::meta version)" "declares schema version 1"

group "version: extraction from real tool output"

assert_eq "1.23.0" "$(version::extract 'go version go1.23.0 darwin/arm64')" "go"
assert_eq "22.18.0" "$(version::extract 'v22.18.0')" "node"
assert_eq "21.0.1" "$(version::extract 'openjdk version "21.0.1" 2023-10-17')" "java"
assert_eq "14.1.0" "$(version::extract 'ripgrep 14.1.0')" "ripgrep"
assert_eq "3.5" "$(version::extract 'tmux 3.5a')" "tmux"
assert_eq "0.11.0" "$(version::extract 'NVIM v0.11.0')" "neovim"
assert_eq "27.0.3" "$(version::extract 'Docker version 27.0.3, build 1a2b3c4')" "docker"
assert_eq "" "$(version::extract 'no version here')" "returns nothing when absent"

group "version: prefix strategy pins a declared version"

version::satisfies "22" "22.18.0" prefix
assert_status "0" "$?" "22 accepts 22.18.0"
version::satisfies "1.23" "1.23.9" prefix
assert_status "0" "$?" "1.23 accepts 1.23.9"
version::satisfies "1.23" "1.24.5" prefix
assert_status "1" "$?" "1.23 rejects 1.24.5"
version::satisfies "2" "21.0" prefix
assert_status "1" "$?" "2 does not match 21 by string prefix"
version::satisfies "" "anything" prefix
assert_status "0" "$?" "no declared version accepts anything"

group "version: minimum and exact strategies"

version::satisfies "14.0" "14.1.0" minimum
assert_status "0" "$?" "14.1.0 satisfies minimum 14.0"
version::satisfies "14.2" "14.1.0" minimum
assert_status "1" "$?" "14.1.0 fails minimum 14.2"
version::satisfies "14.1.0" "14.1.0" exact
assert_status "0" "$?" "exact match"
version::satisfies "14.1.0" "14.1.1" exact
assert_status "1" "$?" "exact rejects a patch difference"

group "version: comparison ordering"

assert_eq "1" "$(version::compare 1.24.0 1.23.9)" "1.24.0 is newer"
assert_eq "-1" "$(version::compare 1.9.0 1.10.0)" "compares numerically, not lexically"
assert_eq "0" "$(version::compare 3.13 3.13.0)" "trailing zeros are equal"

group "platform: manifest platform lists"

platform::init
platform::supported ""
assert_status "0" "$?" "an empty list means everywhere"
platform::supported "$PLATFORM_OS"
assert_status "0" "$?" "the current platform is supported"
platform::supported "plan9"
assert_status "1" "$?" "an unrelated platform is not"

group "cli: the shipped manifest survives a real run"

json="$("$DEV_ROOT/bin/dev" doctor --json --section data 2>/dev/null)"
if have jq; then
    printf '%s' "$json" | jq -e . >/dev/null 2>&1
    assert_status "0" "$?" "doctor --json emits valid JSON"
else
    assert_eq "skipped" "skipped" "doctor --json (jq not installed)"
fi

"$DEV_ROOT/bin/dev" manifest lint >/dev/null 2>&1
assert_status "0" "$?" "dev manifest lint succeeds"

# ------------------------------------------------------------

printf '\n──────────────────────────────\n'
if [ "$TESTS_FAILED" -eq 0 ]; then
    printf '%d assertions, all passed\n\n' "$TESTS_RUN"
    exit 0
fi

printf '%d assertions, %d failed\n\n' "$TESTS_RUN" "$TESTS_FAILED"
exit 1
