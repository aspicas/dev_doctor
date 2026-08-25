#!/usr/bin/env bash
# ============================================================
# Manifest loading, querying and validation.
# ============================================================
#
# The YAML is flattened once by lib/manifest.awk into a cache file, and
# every query reads that cache. Tool attributes are loaded a whole item
# at a time into M_* variables, because bash 3.2 has no associative
# arrays and one awk process per field would dominate the runtime.
#
# Values are assigned through an explicit case statement rather than
# eval. The schema is small enough that being explicit costs little and
# removes any chance of a manifest value being executed as shell code
# at load time.
# ============================================================

MANIFEST_CACHE=""

MANIFEST_TOOL_KEYS="name binary section category requirement replaces manager platforms doc install.macos install.linux version.command version.expected version.strategy detect.path detect.kind integrations"
MANIFEST_REQUIREMENTS="required recommended optional"
MANIFEST_PROVIDERS="brew brew-cask mise xcode script manual system"

manifest::load() {
    [ -r "$DEV_MANIFEST" ] || dev::die "manifest not readable: $DEV_MANIFEST"

    MANIFEST_CACHE="$DEV_RUN_DIR/manifest.tsv"

    if ! awk -f "$DEV_LIB_DIR/manifest.awk" "$DEV_MANIFEST" > "$MANIFEST_CACHE"; then
        dev::error "manifest could not be parsed: $DEV_MANIFEST"
        awk -F'\t' '$1 == "ERROR" { printf "  line %s: %s\n    %s\n", $2, $3, $4 }' \
            "$MANIFEST_CACHE" >&2
        exit 1
    fi
}

# ------------------------------------------------------------
# Queries
# ------------------------------------------------------------

manifest::meta() {
    awk -F'\t' -v k="$1" '$1 == "META" && $3 == k { print $4; exit }' "$MANIFEST_CACHE"
}

manifest::section_ids() {
    awk -F'\t' '$1 == "SECTION" && $3 == "id" { print $4 }' "$MANIFEST_CACHE"
}

manifest::section_title() {
    awk -F'\t' -v want="$1" '
        $1 == "SECTION" && $3 == "id"    { id[$2] = $4 }
        $1 == "SECTION" && $3 == "title" { title[$2] = $4 }
        END { for (i in id) if (id[i] == want) { print title[i]; break } }
    ' "$MANIFEST_CACHE"
}

# True when `$1` is a declared section id. On failure the error already
# names `dev sections`, so callers only have to decide the exit status.
manifest::require_section() {
    local want="$1"

    if [ -z "$want" ]; then
        dev::error "section id is required"
        dev::log "run \`dev sections\` to see the declared ids"
        return 1
    fi

    if manifest::section_ids | grep -qx "$want"; then
        return 0
    fi

    dev::error "unknown section: $want"
    dev::log "run \`dev sections\` to see the declared ids"
    return 1
}

manifest::tool_indices() {
    awk -F'\t' '$1 == "TOOL" && $3 == "name" { print $2 }' "$MANIFEST_CACHE"
}

manifest::tool_indices_in_section() {
    awk -F'\t' -v want="$1" '
        $1 == "TOOL" && $3 == "section" && $4 == want { print $2 }
    ' "$MANIFEST_CACHE"
}

manifest::index_of() {
    awk -F'\t' -v want="$1" '
        $1 == "TOOL" && $3 == "name" && $4 == want { print $2; exit }
    ' "$MANIFEST_CACHE"
}

manifest::field() {
    awk -F'\t' -v i="$1" -v k="$2" '
        $1 == "TOOL" && $2 == i && $3 == k { print $4; exit }
    ' "$MANIFEST_CACHE"
}

# ------------------------------------------------------------
# Whole item loading
# ------------------------------------------------------------

M_index=""
M_name=""
M_binary=""
M_section=""
M_category=""
M_requirement=""
M_replaces=""
M_manager=""
M_platforms=""
M_doc=""
M_install_macos=""
M_install_linux=""
M_version_command=""
M_version_expected=""
M_version_strategy=""
M_detect_path=""
M_detect_kind=""
M_integrations=""

manifest::_reset() {
    M_index=""
    M_name=""
    M_binary=""
    M_section=""
    M_category=""
    M_requirement=""
    M_replaces=""
    M_manager=""
    M_platforms=""
    M_doc=""
    M_install_macos=""
    M_install_linux=""
    M_version_command=""
    M_version_expected=""
    M_version_strategy=""
    M_detect_path=""
    M_detect_kind=""
    M_integrations=""
}

manifest::tool_load() {
    local index="$1"
    local key value

    manifest::_reset
    M_index="$index"

    while IFS=$'\t' read -r key value; do
        [ -z "$key" ] && continue
        case "$key" in
            name)              M_name="$value" ;;
            binary)            M_binary="$value" ;;
            section)           M_section="$value" ;;
            category)          M_category="$value" ;;
            requirement)       M_requirement="$value" ;;
            replaces)          M_replaces="$value" ;;
            manager)           M_manager="$value" ;;
            platforms)         M_platforms="$value" ;;
            doc)               M_doc="$value" ;;
            install.macos)     M_install_macos="$value" ;;
            install.linux)     M_install_linux="$value" ;;
            version.command)   M_version_command="$value" ;;
            version.expected)  M_version_expected="$value" ;;
            version.strategy)  M_version_strategy="$value" ;;
            detect.path)       M_detect_path="$value" ;;
            detect.kind)       M_detect_kind="$value" ;;
            integrations)      M_integrations="$value" ;;
            *) dev::debug "ignoring unknown key '$key' on tool index $index" ;;
        esac
    done <<< "$(awk -F'\t' -v i="$index" '
        $1 == "TOOL" && $2 == i { print $3 "\t" $4 }
    ' "$MANIFEST_CACHE")"

    [ -n "$M_requirement" ] || M_requirement="recommended"
    [ -n "$M_version_strategy" ] || M_version_strategy="prefix"
}

# Install directive for the current platform, e.g. "brew:ripgrep".
manifest::install_directive() {
    case "$PLATFORM_OS" in
        macos) printf '%s\n' "$M_install_macos" ;;
        linux) printf '%s\n' "$M_install_linux" ;;
        *) printf '\n' ;;
    esac
}

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------
#
# Structural mistakes in the manifest must fail loudly. A silently
# ignored field would make the doctor report confidently wrong, which is
# worse than not running at all.

manifest::lint() {
    local problems=0
    local index name seen="" key provider directive platform

    if [ "$(manifest::meta version)" != "1" ]; then
        dev::error "unsupported manifest version, expected 1"
        problems=$((problems + 1))
    fi

    local section_ids
    section_ids="$(manifest::section_ids)"
    [ -n "$section_ids" ] || {
        dev::error "manifest declares no sections"
        problems=$((problems + 1))
    }

    for index in $(manifest::tool_indices); do
        manifest::tool_load "$index"
        name="$M_name"

        if [ -z "$name" ]; then
            dev::error "tool at index $index has no name"
            problems=$((problems + 1))
            continue
        fi

        case " $seen " in
            *" $name "*)
                dev::error "duplicate tool name: $name"
                problems=$((problems + 1))
                ;;
        esac
        seen="$seen $name"

        # Every tool must be detectable somehow.
        if [ -z "$M_binary" ] && [ -z "$M_detect_path" ]; then
            dev::error "$name declares neither a binary nor detect.path"
            problems=$((problems + 1))
        fi

        # The section must exist in the layout.
        if [ -z "$M_section" ]; then
            dev::error "$name has no section"
            problems=$((problems + 1))
        elif ! printf '%s\n' "$section_ids" | grep -qx "$M_section"; then
            dev::error "$name references unknown section '$M_section'"
            problems=$((problems + 1))
        fi

        case " $MANIFEST_REQUIREMENTS " in
            *" $M_requirement "*) ;;
            *)
                dev::error "$name has invalid requirement '$M_requirement'"
                problems=$((problems + 1))
                ;;
        esac

        # Install providers must be understood by the install engine.
        for platform in macos linux; do
            case "$platform" in
                macos) directive="$M_install_macos" ;;
                linux) directive="$M_install_linux" ;;
            esac
            [ -z "$directive" ] && continue
            provider="${directive%%:*}"
            case " $MANIFEST_PROVIDERS " in
                *" $provider "*) ;;
                *)
                    dev::error "$name has unknown install provider '$provider' for $platform"
                    problems=$((problems + 1))
                    ;;
            esac
        done

        # Unknown keys are typos and must not be ignored.
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            case " $MANIFEST_TOOL_KEYS " in
                *" $key "*) ;;
                *)
                    dev::error "$name has unknown key '$key'"
                    problems=$((problems + 1))
                    ;;
            esac
        done <<< "$(awk -F'\t' -v i="$index" '$1 == "TOOL" && $2 == i { print $3 }' "$MANIFEST_CACHE")"
    done

    if [ "$problems" -gt 0 ]; then
        dev::error "manifest validation found $problems problem(s)"
        return 1
    fi

    return 0
}
