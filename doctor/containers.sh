#!/usr/bin/env bash
# ============================================================
# Container runtime checks.
# ============================================================

# A docker CLI without a reachable daemon is the usual failure mode,
# and it is invisible until a compose file refuses to start.
integration::docker_daemon() {
    if run::limited 10 docker info >/dev/null 2>&1; then
        integration::ok "docker → daemon" "reachable"
        return 0
    fi

    if platform::is_macos && [ -d /Applications/OrbStack.app ]; then
        integration::warn "docker → daemon" "not running"
        report::fix "docker → daemon" "open -a OrbStack" safe
        return 0
    fi

    integration::warn "docker → daemon" "not reachable"
    report::fix "docker → daemon" "start your container runtime" manual
}
