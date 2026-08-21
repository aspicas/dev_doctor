#!/usr/bin/env bash
# ============================================================
# `dev setup <topic>` — guided, explicit configuration.
# ============================================================
#
# These are the changes that `dev doctor --fix` deliberately refuses to
# make on its own. They live behind an explicit command so that the
# decision is always a human one, taken on purpose.
# ============================================================

setup::usage() {
    cat <<'USAGE'
Usage: dev setup <topic>

Topics:
  git-signing     configure SSH based commit signing

These changes are never applied by `dev doctor --fix`.
USAGE
}

setup::main() {
    local topic="${1:-}"
    [ $# -gt 0 ] && shift

    style::init auto

    case "$topic" in
        git-signing) setup::git_signing "$@" ;;
        ""|-h|--help) setup::usage ;;
        *) dev::error "unknown topic: $topic"; setup::usage >&2; return 64 ;;
    esac
}

setup::git_signing() {
    local keys=() key reply choice index

    have git || dev::die "git is not installed"

    for key in "$HOME"/.ssh/*.pub; do
        [ -f "$key" ] || continue
        grep -q 'ssh-ed25519' "$key" 2>/dev/null && keys+=("$key")
    done

    if [ "${#keys[@]}" -eq 0 ]; then
        printf '\n%sNo ed25519 public key found in ~/.ssh%s\n\n' "$C_YELLOW" "$C_RESET"
        printf 'Create one first, then run this command again:\n\n'
        printf '  ssh-keygen -t ed25519 -C "%s"\n\n' "$(hostname)"
        printf 'On macOS, prefer a Secure Enclave key managed by Secretive.\n\n'
        return 1
    fi

    printf '\n%sSSH keys available for signing%s\n\n' "$C_BOLD" "$C_RESET"
    index=1
    for key in "${keys[@]}"; do
        printf '  %d) %s\n' "$index" "$key"
        index=$((index + 1))
    done
    printf '\n'

    if [ ! -t 0 ]; then
        dev::error "this command needs a terminal"
        return 1
    fi

    printf 'Select a key [1-%d]: ' "${#keys[@]}"
    read -r choice
    case "$choice" in
        ''|*[!0-9]*) dev::die "not a number: $choice" ;;
    esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#keys[@]}" ]; then
        dev::die "selection out of range"
    fi

    key="${keys[$((choice - 1))]}"

    local allowed_signers="${XDG_CONFIG_HOME:-$HOME/.config}/git/allowed_signers"
    local email
    email="$(git config --global --get user.email 2>/dev/null)"

    printf '\nThis will run:\n\n'
    printf '  git config --global gpg.format ssh\n'
    printf '  git config --global user.signingkey %s\n' "$key"
    printf '  git config --global commit.gpgsign true\n'
    printf '  git config --global tag.gpgsign true\n'
    printf '  git config --global gpg.ssh.allowedSignersFile %s\n' "$allowed_signers"
    printf '\nContinue? [y/N] '
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) printf 'Nothing was changed.\n'; return 0 ;;
    esac

    git config --global gpg.format ssh
    git config --global user.signingkey "$key"
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    git config --global gpg.ssh.allowedSignersFile "$allowed_signers"

    mkdir -p "$(dirname "$allowed_signers")"
    if [ -n "$email" ]; then
        if ! grep -qF "$(cat "$key")" "$allowed_signers" 2>/dev/null; then
            printf '%s %s\n' "$email" "$(cat "$key")" >> "$allowed_signers"
        fi
        printf '\n%s%s%s allowed signers updated for %s\n' \
            "$C_GREEN" "$SYM_OK" "$C_RESET" "$email"
    else
        printf '\n%s%s%s user.email is not set, so allowed_signers was left alone\n' \
            "$C_YELLOW" "$SYM_WARN" "$C_RESET"
    fi

    printf '%s%s%s commit signing configured\n\n' "$C_GREEN" "$SYM_OK" "$C_RESET"

    if [ -n "${DEV_DOTFILES_REMINDER:-1}" ]; then
        printf '%sRemember to mirror this into your chezmoi source so it survives\n' "$C_DIM"
        printf 'the next `chezmoi apply`.%s\n\n' "$C_RESET"
    fi
}
