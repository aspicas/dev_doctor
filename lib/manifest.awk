# ============================================================
# Manifest parser
# ============================================================
#
# Parses the restricted YAML subset used by toolchain.yaml and flattens
# it into tab separated records:
#
#   KIND <TAB> INDEX <TAB> KEY <TAB> VALUE
#
# KIND is META, SECTION, TOOL or ERROR. INDEX identifies the item inside
# a sequence and is 0 for META. Nested maps are flattened with dots, so
# `version: { expected: "22" }` becomes the key `version.expected`.
# Sequences of scalars are joined with single spaces, which is safe
# because the schema only allows identifiers inside sequences.
#
# This parser deliberately accepts far less than real YAML. Anything it
# does not understand becomes an ERROR record so that `dev manifest lint`
# fails loudly instead of silently dropping configuration.
#
# Requires only POSIX awk.
# ============================================================

function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}

# Remove a trailing YAML comment, ignoring "#" that appears inside quotes.
function strip_comment(s,    i, c, prev, inq, q) {
    inq = 0
    q = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (inq) {
            if (c == q) inq = 0
            continue
        }
        if (c == "'" || c == "\"") {
            inq = 1
            q = c
            continue
        }
        if (c == "#") {
            if (i == 1) return ""
            prev = substr(s, i - 1, 1)
            if (prev == " " || prev == "\t") return substr(s, 1, i - 1)
        }
    }
    return s
}

function unquote(s,    first, last) {
    if (length(s) < 2) return s
    first = substr(s, 1, 1)
    last = substr(s, length(s), 1)
    if (first == "\"" && last == "\"") return substr(s, 2, length(s) - 2)
    if (first == "'" && last == "'") return substr(s, 2, length(s) - 2)
    return s
}

# Turn a scalar or inline flow sequence into a plain value.
# "[a, b]" becomes "a b".
function normalize(s,    n, i, parts, piece, out) {
    s = trim(s)
    if (s == "") return ""
    if (substr(s, 1, 1) == "[" && substr(s, length(s), 1) == "]") {
        s = substr(s, 2, length(s) - 2)
        n = split(s, parts, ",")
        out = ""
        for (i = 1; i <= n; i++) {
            piece = unquote(trim(parts[i]))
            if (piece == "") continue
            out = (out == "") ? piece : out " " piece
        }
        return out
    }
    return unquote(s)
}

function fail(msg) {
    printf "ERROR\t%d\t%s\t%s\n", NR, msg, $0
    errors++
}

function emit(kind, item, key, value) {
    recn++
    rec[recn] = kind "\t" item "\t" key "\t" value
    return recn
}

# Append to an existing sequence record, or create it.
function emit_list(kind, item, key, value,    slot, at) {
    slot = kind SUBSEP item SUBSEP key
    if (slot in listat) {
        at = listat[slot]
        listval[slot] = listval[slot] " " value
        rec[at] = kind "\t" item "\t" key "\t" listval[slot]
        return at
    }
    listval[slot] = value
    listat[slot] = emit(kind, item, key, value)
    return listat[slot]
}

# Split "key: value" into globals kv_key and kv_value.
# Returns 0 when the text is not a mapping entry.
function split_kv(text) {
    if (!match(text, /^[A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/)) return 0
    kv_key = substr(text, 1, index(text, ":") - 1)
    kv_value = normalize(substr(text, index(text, ":") + 1))
    return 1
}

BEGIN {
    FS = "\n"
    topkey = ""
    topchild = ""
    kind = "META"
    idx = 0
    parent = ""
    recn = 0
    errors = 0
}

{
    line = strip_comment($0)
    if (trim(line) == "") next

    if (line ~ /^\t/) {
        fail("tab indentation is not supported")
        next
    }

    indent = 0
    while (substr(line, indent + 1, 1) == " ") indent++
    content = substr(line, indent + 1)

    if (indent % 2 != 0) {
        fail("indentation must be a multiple of two spaces")
        next
    }

    # ---------- top level ----------
    if (indent == 0) {
        if (!split_kv(content)) {
            fail("expected a top level key")
            next
        }
        topkey = kv_key
        topchild = ""
        parent = ""
        idx = 0
        if (topkey == "tools") kind = "TOOL"
        else if (topkey == "sections") kind = "SECTION"
        else kind = "META"
        if (kv_value != "") emit("META", 0, topkey, kv_value)
        next
    }

    if (topkey == "") {
        fail("indented content before any top level key")
        next
    }

    # ---------- mapping under a top level key ----------
    if (kind == "META") {
        if (indent == 2) {
            if (!split_kv(content)) {
                fail("expected a key under " topkey)
                next
            }
            topchild = (kv_value == "") ? kv_key : ""
            if (kv_value != "") emit("META", 0, topkey "." kv_key, kv_value)
            next
        }
        if (indent == 4 && topchild != "") {
            if (substr(content, 1, 2) == "- ") {
                emit_list("META", 0, topkey "." topchild, normalize(substr(content, 3)))
                next
            }
            if (!split_kv(content)) {
                fail("expected a key under " topkey "." topchild)
                next
            }
            emit("META", 0, topkey "." topchild "." kv_key, kv_value)
            next
        }
        fail("unexpected indentation under " topkey)
        next
    }

    # ---------- sequence of items ----------
    if (indent == 2) {
        if (substr(content, 1, 2) != "- ") {
            fail(topkey " must be a sequence of items")
            next
        }
        idx++
        parent = ""
        content = trim(substr(content, 3))
        if (!split_kv(content)) {
            fail("expected a key at the start of a " topkey " item")
            next
        }
        parent = (kv_value == "") ? kv_key : ""
        if (kv_value != "") emit(kind, idx, kv_key, kv_value)
        next
    }

    if (idx == 0) {
        fail("item content before the start of a " topkey " item")
        next
    }

    if (indent == 4) {
        if (substr(content, 1, 2) == "- ") {
            if (parent == "") {
                fail("sequence entry without a parent key")
                next
            }
            emit_list(kind, idx, parent, normalize(substr(content, 3)))
            next
        }
        if (!split_kv(content)) {
            fail("expected a key inside a " topkey " item")
            next
        }
        parent = (kv_value == "") ? kv_key : ""
        if (kv_value != "") emit(kind, idx, kv_key, kv_value)
        next
    }

    if (indent == 6) {
        if (parent == "") {
            fail("nested value without a parent key")
            next
        }
        if (substr(content, 1, 2) == "- ") {
            emit_list(kind, idx, parent, normalize(substr(content, 3)))
            next
        }
        if (!split_kv(content)) {
            fail("expected a key under " parent)
            next
        }
        emit(kind, idx, parent "." kv_key, kv_value)
        next
    }

    fail("indentation deeper than the schema allows")
}

END {
    for (i = 1; i <= recn; i++) print rec[i]
    if (errors > 0) exit 3
}
