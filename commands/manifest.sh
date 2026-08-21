#!/usr/bin/env bash
# ============================================================
# `dev manifest` — inspect and validate the manifest itself.
# ============================================================

manifest_cmd::usage() {
    cat <<'USAGE'
Usage: dev manifest <subcommand>

Subcommands:
  lint      validate toolchain.yaml against the supported schema
  dump      print the flattened records the parser produces
  path      print the manifest currently in use
USAGE
}

manifest_cmd::main() {
    local subcommand="${1:-}"
    [ $# -gt 0 ] && shift

    style::init auto

    case "$subcommand" in
        lint)
            manifest::load
            if manifest::lint; then
                printf '%s%s%s %s is valid\n' \
                    "$C_GREEN" "$SYM_OK" "$C_RESET" "$DEV_MANIFEST"
                return 0
            fi
            return 1
            ;;
        dump)
            manifest::load
            cat "$MANIFEST_CACHE"
            ;;
        path)
            printf '%s\n' "$DEV_MANIFEST"
            ;;
        ""|-h|--help)
            manifest_cmd::usage
            ;;
        *)
            dev::error "unknown subcommand: $subcommand"
            manifest_cmd::usage >&2
            return 64
            ;;
    esac
}
