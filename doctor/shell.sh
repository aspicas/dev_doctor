#!/usr/bin/env bash
# ============================================================
# Shell integration checks.
# ============================================================
#
# Having a tool on disk says nothing about whether the shell knows how
# to use it. These checks read the zsh configuration and confirm that
# each tool is actually initialised.
#
# None of these are auto fixable. The dotfiles are owned by chezmoi, so
# editing the deployed file would be silently reverted on the next
# `chezmoi apply` and would create exactly the kind of drift this tool
# exists to detect. The fix is emitted as advice against the chezmoi
# source instead.
# ============================================================

# Every zsh file that could plausibly perform initialisation.
shell::zsh_files() {
    local zdotdir="${ZDOTDIR:-$HOME/.config/zsh}"
    local candidate

    for candidate in \
        "$zdotdir/.zshrc" \
        "$zdotdir"/*.zsh \
        "$HOME/.zshrc" \
        "$HOME/.zshenv" \
        "$HOME/.zprofile"
    do
        [ -f "$candidate" ] && printf '%s\n' "$candidate"
    done
}

# True when any zsh config file matches the extended regex.
shell::zsh_declares() {
    local pattern="$1"
    local file
    local found=1

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            found=0
            break
        fi
    done <<< "$(shell::zsh_files)"

    return $found
}

# Shared shape for "tool is installed but the shell never initialises it".
shell::require_init() {
    local label="$1"
    local pattern="$2"
    local snippet="$3"

    if shell::zsh_declares "$pattern"; then
        integration::ok "$label" "initialised"
        return 0
    fi

    integration::warn "$label" "not initialised in zsh"
    report::fix "$label" "add to the chezmoi managed zsh config: $snippet" manual
}

# ------------------------------------------------------------
# Integrations referenced by the manifest
# ------------------------------------------------------------

integration::shell_zsh_config() {
    local zdotdir="${ZDOTDIR:-$HOME/.config/zsh}"

    if [ -f "$zdotdir/.zshrc" ] || [ -f "$HOME/.zshrc" ]; then
        integration::ok "zsh → config" "present"
    else
        integration::fail "zsh → config" "no .zshrc found"
        report::fix "zsh → config" "restore the zsh configuration with chezmoi apply" manual
        return 0
    fi

    if [ "${SHELL##*/}" = "zsh" ]; then
        integration::ok "zsh → login shell" "active"
    else
        integration::warn "zsh → login shell" "login shell is ${SHELL##*/}"
        report::fix "zsh → login shell" "chsh -s $(command -v zsh 2>/dev/null || printf zsh)" manual
    fi
}

integration::shell_zsh_plugins() {
    shell::require_init "zinit → zsh" \
        'zinit (light|load|snippet|ice)' \
        'source the zinit plugin manager and declare your plugins'
}

integration::shell_zsh_starship() {
    shell::require_init "starship → zsh" \
        'starship init zsh' \
        'eval "$(starship init zsh)"'
}

integration::shell_zsh_mise() {
    shell::require_init "mise → zsh" \
        'mise activate zsh' \
        'eval "$(mise activate zsh)"'
}

integration::shell_zsh_direnv() {
    shell::require_init "direnv → zsh" \
        'direnv hook zsh' \
        'eval "$(direnv hook zsh)"'
}

integration::shell_zsh_zoxide() {
    shell::require_init "zoxide → zsh" \
        'zoxide init zsh' \
        'eval "$(zoxide init zsh)"'
}

integration::shell_zsh_fzf() {
    shell::require_init "fzf → zsh" \
        'fzf --zsh|fzf\.zsh|fzf/shell|fzf-tab' \
        'eval "$(fzf --zsh)"'
}
