#!/usr/bin/env bash
# ============================================================
# Runtime manager, environment and dotfile integrity checks.
# ============================================================

integration::mise_health() {
    if run::limited 15 mise doctor >/dev/null 2>&1; then
        integration::ok "mise → health" "healthy"
    else
        integration::warn "mise → health" "mise doctor reports problems"
        report::fix "mise → health" "mise doctor" manual
    fi
}

# mise and direnv overlap. Without the bridge, entering a project
# directory loads the environment twice or not at all.
integration::direnv_mise() {
    local direnvrc="$HOME/.config/direnv/direnvrc"
    local lib="$HOME/.config/direnv/lib/use_mise.sh"

    if [ -f "$direnvrc" ] && grep -qE 'mise' "$direnvrc" 2>/dev/null; then
        integration::ok "direnv → mise" "bridged"
        return 0
    fi

    if [ -f "$lib" ]; then
        integration::ok "direnv → mise" "bridged"
        return 0
    fi

    integration::warn "direnv → mise" "no bridge configured"
    report::fix "direnv → mise" \
        "add 'use mise' support: mise direnv activate > ~/.config/direnv/lib/use_mise.sh" manual
}

# The Brewfile is the declared package set. Divergence means the machine
# has drifted from the manifest, in either direction.
integration::brew_bundle() {
    local brewfile
    brewfile="$(manifest::meta meta.brewfile)"
    [ -n "$brewfile" ] || brewfile="Brewfile"

    case "$brewfile" in
        /*) ;;
        *) brewfile="$DEV_ROOT/$brewfile" ;;
    esac

    if [ ! -f "$brewfile" ]; then
        integration::warn "homebrew → Brewfile" "no Brewfile at $brewfile"
        report::fix "homebrew → Brewfile" "dev install --write-brewfile" manual
        return 0
    fi

    if [ -z "${DOCTOR_DEEP:-}" ]; then
        report::skip "homebrew → Brewfile" "not checked, use --deep"
        return 0
    fi

    if run::limited 60 brew bundle check --file="$brewfile" >/dev/null 2>&1; then
        integration::ok "homebrew → Brewfile" "in sync"
    else
        integration::warn "homebrew → Brewfile" "packages differ from the Brewfile"
        report::fix "homebrew → Brewfile" "brew bundle install --file=$brewfile" safe
    fi
}

integration::chezmoi_repository() {
    local source_path

    source_path="$(run::limited 10 chezmoi source-path 2>/dev/null)"

    if [ -n "$source_path" ] && [ -d "$source_path" ]; then
        integration::ok "chezmoi → source" "$source_path"
    else
        integration::fail "chezmoi → source" "no source directory"
        report::fix "chezmoi → source" "chezmoi init <your-dotfiles-repo>" manual
    fi
}

# Uncommitted differences between the source of truth and the machine
# are the single most common cause of "it works on my other laptop".
integration::chezmoi_clean() {
    local status

    status="$(run::limited 20 chezmoi status 2>/dev/null)"

    if [ -z "$status" ]; then
        integration::ok "chezmoi → state" "clean"
    else
        integration::warn "chezmoi → state" "$(printf '%s\n' "$status" | wc -l | tr -d ' ') file(s) differ"
        report::fix "chezmoi → state" "chezmoi diff, then chezmoi apply" manual
    fi
}
