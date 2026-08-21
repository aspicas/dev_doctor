#!/usr/bin/env bash
# ============================================================
# Editor and terminal configuration checks.
# ============================================================

integration::nvim_config() {
    local config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

    if [ -d "$config" ]; then
        integration::ok "neovim → config" "$config"
    else
        integration::fail "neovim → config" "missing"
        report::fix "neovim → config" "chezmoi apply, or restore ~/.config/nvim" manual
    fi
}

integration::nvim_lazyvim() {
    local config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

    if [ ! -d "$config" ]; then
        return 0
    fi

    if [ -f "$config/lazy-lock.json" ] || [ -d "$config/lua/config" ]; then
        integration::ok "neovim → LazyVim" "configured"
    else
        integration::warn "neovim → LazyVim" "no LazyVim layout detected"
        report::fix "neovim → LazyVim" "bootstrap LazyVim from LazyVim/starter" manual
    fi
}

# Plugins declared in the lockfile but never installed mean the editor
# will spend the first minute of the next session downloading them.
integration::nvim_providers() {
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"

    if [ -d "$data" ]; then
        integration::ok "neovim → plugins" "installed"
    else
        integration::warn "neovim → plugins" "not installed yet"
        report::fix "neovim → plugins" "nvim --headless '+Lazy! sync' +qa" safe
    fi
}

integration::tmux_config() {
    local candidate

    for candidate in \
        "$HOME/.tmux.conf" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
    do
        if [ -f "$candidate" ]; then
            integration::ok "tmux → config" "$candidate"
            return 0
        fi
    done

    integration::fail "tmux → config" "missing"
    report::fix "tmux → config" "chezmoi apply, or restore your tmux.conf" manual
}

integration::tmux_tpm() {
    local candidate

    for candidate in \
        "$HOME/.tmux/plugins/tpm" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/tpm"
    do
        if [ -d "$candidate" ]; then
            integration::ok "tmux → tpm" "installed"
            return 0
        fi
    done

    integration::warn "tmux → tpm" "plugin manager not installed"
    report::fix "tmux → tpm" \
        "git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm" safe
}

integration::ghostty_config() {
    local config="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"

    if [ -f "$config" ]; then
        integration::ok "ghostty → config" "present"
    else
        integration::warn "ghostty → config" "missing"
        report::fix "ghostty → config" "chezmoi apply, or create ~/.config/ghostty/config" manual
    fi
}
