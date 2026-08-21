#!/usr/bin/env bash
# ============================================================
# Mobile toolchain checks: iOS, Android, Flutter.
# ============================================================
#
# Mobile toolchains fail in ways that a plain `command -v` never
# catches: Xcode installed but the command line tools pointing at the
# wrong developer directory, an SDK on disk with no ANDROID_HOME, a
# Flutter checkout that cannot find any of it.
# ============================================================

# ------------------------------------------------------------
# iOS
# ------------------------------------------------------------

integration::ios_command_line_tools() {
    local developer_dir

    developer_dir="$(run::limited 10 xcode-select -p 2>/dev/null)"

    if [ -z "$developer_dir" ]; then
        integration::fail "xcode → command line tools" "not selected"
        report::fix "xcode → command line tools" "xcode-select --install" manual
        return 0
    fi

    case "$developer_dir" in
        *Xcode.app*)
            integration::ok "xcode → command line tools" "$developer_dir"
            ;;
        *)
            # The standalone CLT cannot build iOS apps or run simulators.
            integration::warn "xcode → command line tools" "$developer_dir" "Xcode.app"
            report::fix "xcode → command line tools" \
                "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" manual
            ;;
    esac
}

integration::ios_license() {
    if run::limited 10 xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        integration::ok "xcode → first launch" "complete"
    else
        integration::warn "xcode → first launch" "pending components or license"
        report::fix "xcode → first launch" "sudo xcodebuild -runFirstLaunch" manual
    fi
}

integration::ios_simulators() {
    local count

    # The parentheses must be escaped and the alternation grouped, or the
    # `|` splits the whole pattern instead of the two states.
    count="$(run::limited 20 xcrun simctl list devices available 2>/dev/null |
        grep -cE '\([0-9A-F-]{36}\) \((Shutdown|Booted)\)')"

    case "$count" in *[!0-9]*|"") count=0 ;; esac

    if [ "$count" -eq 0 ]; then
        integration::warn "xcode → simulators" "no runtimes installed"
        report::fix "xcode → simulators" "xcodebuild -downloadPlatform iOS" manual
    else
        integration::ok "xcode → simulators" "$count available"
    fi
}

# ------------------------------------------------------------
# Android
# ------------------------------------------------------------

integration::android_home() {
    local home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

    if [ -z "$home" ]; then
        integration::warn "android → ANDROID_HOME" "not set"
        report::fix "android → ANDROID_HOME" \
            "export ANDROID_HOME=\"\$HOME/Library/Android/sdk\" in your zsh config" manual
        return 0
    fi

    if [ -d "$home" ]; then
        integration::ok "android → ANDROID_HOME" "$home"
    else
        integration::fail "android → ANDROID_HOME" "points at a missing directory"
        report::fix "android → ANDROID_HOME" "correct ANDROID_HOME or install the SDK" manual
    fi
}

integration::android_platform_tools() {
    local home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

    if have adb; then
        integration::ok "android → platform tools" "adb in PATH"
        return 0
    fi

    if [ -x "$home/platform-tools/adb" ]; then
        integration::warn "android → platform tools" "installed but not in PATH"
        report::fix "android → platform tools" \
            "add \$ANDROID_HOME/platform-tools to PATH" manual
        return 0
    fi

    integration::warn "android → platform tools" "not installed"
    report::fix "android → platform tools" "sdkmanager 'platform-tools'" manual
}

# ------------------------------------------------------------
# Flutter
# ------------------------------------------------------------

# `flutter doctor` is slow enough to dominate the runtime of the whole
# report, so it only runs when explicitly requested.
integration::flutter_doctor() {
    if [ -z "${DOCTOR_DEEP:-}" ]; then
        report::skip "flutter → doctor" "not checked, use --deep"
        return 0
    fi

    local output
    output="$(run::limited 120 flutter doctor 2>/dev/null)"

    if [ -z "$output" ]; then
        integration::warn "flutter → doctor" "did not complete"
        report::fix "flutter → doctor" "flutter doctor -v" manual
        return 0
    fi

    local problems
    problems="$(printf '%s\n' "$output" | grep -cE '^\[(!|x|✗)\]')"

    case "$problems" in *[!0-9]*|"") problems=0 ;; esac

    if [ "$problems" -eq 0 ]; then
        integration::ok "flutter → doctor" "no problems reported"
    else
        integration::warn "flutter → doctor" "$problems category(s) need attention"
        report::fix "flutter → doctor" "flutter doctor -v" manual
    fi
}
