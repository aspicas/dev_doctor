#!/usr/bin/env bash
# ============================================================
# Security posture checks.
# ============================================================
#
# Nothing in this module is ever auto fixed. Key material, agent
# configuration and file permissions on ~/.ssh are the last place a
# diagnostic tool should be making unattended decisions.
# ============================================================

integration::ssh_keys() {
    local ssh_dir="$HOME/.ssh"
    local key found_ed25519=1 weak=""

    if [ ! -d "$ssh_dir" ]; then
        integration::warn "ssh → keys" "no ~/.ssh directory"
        return 0
    fi

    for key in "$ssh_dir"/*.pub; do
        [ -f "$key" ] || continue
        if grep -q 'ssh-ed25519' "$key" 2>/dev/null; then
            found_ed25519=0
        elif grep -qE 'ssh-rsa|ssh-dss' "$key" 2>/dev/null; then
            weak="$weak ${key##*/}"
        fi
    done

    if [ "$found_ed25519" -eq 0 ]; then
        integration::ok "ssh → keys" "ed25519 present"
    else
        integration::warn "ssh → keys" "no ed25519 key found"
        report::fix "ssh → keys" "ssh-keygen -t ed25519 -C \"\$(hostname)\"" manual
    fi

    if [ -n "$weak" ]; then
        integration::warn "ssh → key policy" "legacy key(s):$weak"
        report::fix "ssh → key policy" "review and retire legacy SSH keys" manual
    fi
}

integration::ssh_agent() {
    if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ]; then
        integration::ok "ssh → agent" "socket available"
    else
        integration::warn "ssh → agent" "SSH_AUTH_SOCK not available"
        report::fix "ssh → agent" "point SSH_AUTH_SOCK at your agent, for example Secretive" manual
    fi

    # Permissions on ~/.ssh are a frequent silent failure.
    if [ -d "$HOME/.ssh" ]; then
        local mode
        mode="$(ls -ld "$HOME/.ssh" | awk '{print $1}')"
        case "$mode" in
            drwx------*) integration::ok "ssh → permissions" "700" ;;
            *)
                integration::warn "ssh → permissions" "$mode" "drwx------"
                report::fix "ssh → permissions" "chmod 700 ~/.ssh" manual
                ;;
        esac
    fi
}
