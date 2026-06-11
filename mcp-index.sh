#!/usr/bin/env bash
# mcp-index.sh — manage codebase-memory-mcp indexes

MCP_BIN="${MCP_BIN:-$(command -v codebase-memory-mcp 2>/dev/null)}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/projects}"
CHANGE_LIST_LIMIT="${CHANGE_LIST_LIMIT:-15}"
[[ "$CHANGE_LIST_LIMIT" =~ ^[0-9]+$ ]] || CHANGE_LIST_LIMIT=15

# ── Colors ────────────────────────────────────────────────────────────────────

_bold()   { printf '\033[1m%s\033[0m'  "$*"; }
_green()  { printf '\033[32m%s\033[0m' "$*"; }
_red()    { printf '\033[31m%s\033[0m' "$*"; }
_yellow() { printf '\033[33m%s\033[0m' "$*"; }
_cyan()   { printf '\033[36m%s\033[0m' "$*"; }
_dim()    { printf '\033[2m%s\033[0m'  "$*"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

_divider() {
    local w; w=$(( $(tput cols 2>/dev/null || echo 72) - 4 ))
    printf '  %s\n' "$(printf '%.0s─' $(seq 1 "$w"))"
}

_pause() { read -rp "  Press Enter to continue..."; }

_confirm() {
    local ans
    read -rp "  $1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

_mcp() {
    local output status
    output=$("$MCP_BIN" cli "$@" 2>&1)
    status=$?
    printf '%s\n' "$output" | grep -v '^level=' || true
    return "$status"
}

_check_mcp() {
    if [[ -z "$MCP_BIN" || ! -x "$MCP_BIN" ]]; then
        _red "codebase-memory-mcp not found in PATH"; echo
        exit 1
    fi
}

# ── Project data ──────────────────────────────────────────────────────────────
# Populated by _load_projects; used by all actions.
_proj_names=()
_proj_labels=()
_proj_paths=()
_proj_stale=()

_load_projects() {
    _proj_names=() _proj_labels=() _proj_paths=() _proj_stale=()
    while IFS='|' read -r name label path stale; do
        [[ -z "$name" ]] && continue
        _proj_names+=("$name")
        _proj_labels+=("$label")
        _proj_paths+=("$path")
        _proj_stale+=("$stale")
    done < <(_mcp list_projects '{}' | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
for p in d.get('projects', []):
    root  = p.get('root_path', '')
    label = os.path.basename(root) or p.get('name', '?')
    stale = '' if os.path.isdir(root) else 'stale'
    print(p['name'] + '|' + label + '|' + root + '|' + stale)
" 2>/dev/null)
}

# _pick_projects <prompt>
# Reads from _proj_names[]. Supports: single number, comma-list, A=all.
# Fills _picked[] with 0-based indices. Returns 1 on invalid input.
_picked=()
_pick_projects() {
    local prompt="${1:-Choice}"
    _picked=()
    local n="${#_proj_names[@]}"
    (( n == 0 )) && return 1

    for i in "${!_proj_names[@]}"; do
        local tag=''
        [[ "${_proj_stale[$i]}" == "stale" ]] && tag=' (stale)'
        printf '  %d) %s%s\n' "$((i+1))" "${_proj_labels[$i]}" "$tag"
    done
    printf '  A) All\n\n'
    read -rp "  $prompt: " choice

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        _picked=("${!_proj_names[@]}")
        return 0
    fi

    IFS=',' read -ra _parts <<< "$choice"
    for part in "${_parts[@]}"; do
        part="${part// /}"
        if [[ "$part" =~ ^[0-9]+$ ]] && (( part >= 1 && part <= n )); then
            _picked+=("$((part-1))")
        else
            printf '  '; _red "Invalid: $part"; echo
            return 1
        fi
    done
    (( ${#_picked[@]} > 0 ))
}

# ── Header ────────────────────────────────────────────────────────────────────

_print_header() {
    clear; echo
    printf '  '; _bold "mcp-index"; echo
    printf '  '; _dim "codebase-memory-mcp $("$MCP_BIN" --version 2>/dev/null | awk '{print $2}')"; echo
    echo
    _divider; echo
}

# ── Project list view ─────────────────────────────────────────────────────────

_render_projects() {
    local raw; raw=$(_mcp list_projects '{}')
    local count; count=$(echo "$raw" | python3 -c "
import sys,json; print(len(json.load(sys.stdin).get('projects',[])))
" 2>/dev/null || echo 0)

    if (( count == 0 )); then
        printf '  '; _dim "No projects indexed yet."; echo; echo
        return
    fi

    printf '  %-4s  %-24s  %-8s  %-8s  %s\n' "#" "Project" "Nodes" "Edges" "Size"
    _divider

    echo "$raw" | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
for i, p in enumerate(d.get('projects', []), 1):
    root  = p.get('root_path', '')
    name  = os.path.basename(root) or p.get('name', '?')
    nodes = p.get('nodes', 0)
    edges = p.get('edges', 0)
    mb    = p.get('size_bytes', 0) / 1048576
    stale = '' if os.path.isdir(root) else 'stale'
    print(f'{i}|{name}|{nodes}|{edges}|{mb:.1f} MB|{root}|{stale}')
" 2>/dev/null | while IFS='|' read -r idx name nodes edges size path stale; do
        printf '  %-4s  %-24s  %-8s  %-8s  %s' "$idx)" "$name" "$nodes" "$edges" "$size"
        [[ "$stale" == "stale" ]] && { printf '  '; _red "[stale]"; }
        echo
        printf '       '; _dim "$path"; echo
    done
    echo
}

# ── Shared index helper ───────────────────────────────────────────────────────

_index_one() {
    local target="$1"
    printf '  Indexing '; _cyan "$(basename "$target")"; printf '... '
    local result; result=$(_mcp index_repository "{\"repo_path\":\"$target\"}")
    local st; st=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','?'))" 2>/dev/null)
    local n;  n=$(echo "$result"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('nodes',0))"   2>/dev/null)
    local e;  e=$(echo "$result"  | python3 -c "import sys,json; print(json.load(sys.stdin).get('edges',0))"   2>/dev/null)

    if [[ "$st" == "indexed" ]]; then
        _green "✓"; printf ' %s nodes, %s edges\n' "$n" "$e"
        # Auto-delete stale twin (same basename, dead path)
        local base; base=$(basename "$target")
        _load_projects
        for i in "${!_proj_names[@]}"; do
            if [[ "${_proj_labels[$i]}" == "$base" && "${_proj_stale[$i]}" == "stale" ]]; then
                _mcp delete_project "{\"project\":\"${_proj_names[$i]}\"}" > /dev/null
                printf '       '; _yellow "Auto-deleted stale twin: "; _dim "${_proj_names[$i]}"; echo
            fi
        done
    else
        _red "failed"; echo
        echo "$result" | head -3 | sed 's/^/    /'
    fi
}

# ── Actions ───────────────────────────────────────────────────────────────────

do_index() {
    echo
    local subdirs=()
    [[ -d "$WORKSPACE_ROOT" ]] && mapfile -t subdirs < <(find "$WORKSPACE_ROOT" -maxdepth 1 -mindepth 1 -type d | sort)

    local targets=()

    if (( ${#subdirs[@]} > 0 )); then
        printf '  Subdirectories of %s:\n\n' "$WORKSPACE_ROOT"
        for i in "${!subdirs[@]}"; do
            printf '  %d) %s\n' "$((i+1))" "$(basename "${subdirs[$i]}")"
        done
        printf '  A) All\n'
        printf '  P) Custom path\n\n'
        read -rp "  Choice (number, comma-list, A, P): " choice

        if [[ "$choice" =~ ^[Aa]$ ]]; then
            targets=("${subdirs[@]}")
        elif [[ "$choice" =~ ^[Pp]$ ]]; then
            read -rp "  Path: " input_path
            local p="${input_path/#\~/$HOME}"
            if [[ ! -d "$p" ]]; then
                printf '  '; _red "Directory not found: $p"; echo
                _pause; return
            fi
            targets=("$p")
        else
            IFS=',' read -ra _parts <<< "$choice"
            for part in "${_parts[@]}"; do
                part="${part// /}"
                if [[ "$part" =~ ^[0-9]+$ ]] && (( part >= 1 && part <= ${#subdirs[@]} )); then
                    targets+=("${subdirs[$((part-1))]}")
                else
                    printf '  '; _red "Invalid: $part"; echo
                    _pause; return
                fi
            done
        fi
    else
        printf '  Path to index (default: %s): ' "$WORKSPACE_ROOT"
        read -r input_path
        local p="${input_path:-$WORKSPACE_ROOT}"
        p="${p/#\~/$HOME}"
        if [[ ! -d "$p" ]]; then
            printf '  '; _red "Directory not found: $p"; echo
            _pause; return
        fi
        targets=("$p")
    fi

    (( ${#targets[@]} == 0 )) && { _pause; return; }
    echo
    for target in "${targets[@]}"; do
        _index_one "$target"
    done
    echo; _pause
}

do_detect_changes() {
    _load_projects
    if (( ${#_proj_names[@]} == 0 )); then
        printf '  '; _dim "No projects indexed."; echo; _pause; return
    fi

    echo
    printf '  '; _dim "Reads current Git diff — does not refresh the index."; echo; echo
    if ! _pick_projects "Select project(s) (number, comma-list, A)"; then
        printf '  '; _red "Invalid choice"; echo; _pause; return
    fi

    echo
    for i in "${_picked[@]}"; do
        printf '  Checking '; _cyan "${_proj_labels[$i]}"; printf '... '
        local result
        if ! result=$(_mcp detect_changes "{\"project\":\"${_proj_names[$i]}\"}"); then
            _red "failed"; echo
            printf '%s\n' "$result" | head -3 | sed 's/^/    /'
            echo; continue
        fi
        local changed; changed=$(echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
files = d.get('changed_files', d.get('changes', []))
print(d.get('changed_count', len(files) if isinstance(files, list) else 0))
" 2>/dev/null || echo "?")
        _green "done"; printf ' (%s files changed)\n' "$changed"
        echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
files = d.get('changed_files', d.get('changes', []))
if not isinstance(files, list): raise SystemExit
limit = $CHANGE_LIST_LIMIT
for p in files[:limit]: print(f'    - {p}')
if len(files) > limit: print(f'    ... and {len(files) - limit} more')
" 2>/dev/null
        echo
    done
    _pause
}

do_delete() {
    _load_projects
    if (( ${#_proj_names[@]} == 0 )); then
        printf '  '; _dim "No projects indexed."; echo; _pause; return
    fi

    echo
    if ! _pick_projects "Select project(s) to delete (number, comma-list, A)"; then
        printf '  '; _red "Invalid choice"; echo; _pause; return
    fi

    echo
    printf '  Will delete:\n'
    for i in "${_picked[@]}"; do printf '    • %s\n' "${_proj_labels[$i]}"; done
    echo
    if ! _confirm "Confirm delete?"; then
        printf '  '; _dim "Cancelled"; echo; echo; _pause; return
    fi

    echo
    for i in "${_picked[@]}"; do
        printf '  Deleting '; _cyan "${_proj_labels[$i]}"; printf '... '
        _mcp delete_project "{\"project\":\"${_proj_names[$i]}\"}" > /dev/null
        _green "done"; echo
    done
    echo; _pause
}

do_search() {
    _load_projects
    if (( ${#_proj_names[@]} == 0 )); then
        printf '  '; _dim "No projects indexed."; echo; _pause; return
    fi

    echo
    local proj
    if (( ${#_proj_names[@]} == 1 )); then
        proj="${_proj_names[0]}"
        printf '  Project: %s\n' "${_proj_labels[0]}"
    else
        printf '  Select project:\n\n'
        for i in "${!_proj_names[@]}"; do
            printf '  %d) %s\n' "$((i+1))" "${_proj_labels[$i]}"
        done
        echo
        read -rp "  Choice: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#_proj_names[@]} )); then
            printf '  '; _red "Invalid choice"; echo; _pause; return
        fi
        proj="${_proj_names[$((choice-1))]}"
    fi

    echo
    read -rp "  Search query: " query
    [[ -z "$query" ]] && { _pause; return; }

    echo
    local result; result=$(_mcp search_graph "{\"project\":\"$proj\",\"query\":\"$query\",\"limit\":10}")
    echo "$result" | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
if not results:
    print('  No results.')
else:
    for r in results:
        name  = r.get('name','?')
        label = r.get('label','?')
        fpath = r.get('file_path','?')
        line  = r.get('start_line','')
        loc   = f'{fpath}:{line}' if line else fpath
        print(f'  {name}  [{label}]  {loc}')
" 2>/dev/null
    echo; _pause
}

do_install_hooks() {
    _load_projects

    local live_idxs=()
    for i in "${!_proj_names[@]}"; do
        [[ "${_proj_stale[$i]}" != "stale" && -d "${_proj_paths[$i]}/.git" ]] && live_idxs+=("$i")
    done

    if (( ${#live_idxs[@]} == 0 )); then
        echo
        printf '  '; _dim "No indexed git repositories found."; echo
        echo; _pause; return
    fi

    echo
    printf '  Git repos available:\n\n'
    local display_names=() display_paths=()
    for i in "${live_idxs[@]}"; do
        display_names+=("${_proj_labels[$i]}")
        display_paths+=("${_proj_paths[$i]}")
    done

    local _saved_names=("${_proj_names[@]}")
    local _saved_labels=("${_proj_labels[@]}")
    local _saved_paths=("${_proj_paths[@]}")
    local _saved_stale=("${_proj_stale[@]}")
    _proj_names=() _proj_labels=() _proj_paths=() _proj_stale=()
    for i in "${live_idxs[@]}"; do
        _proj_names+=("${_saved_names[$i]}")
        _proj_labels+=("${_saved_labels[$i]}")
        _proj_paths+=("${_saved_paths[$i]}")
        _proj_stale+=("${_saved_stale[$i]}")
    done

    if ! _pick_projects "Select project(s) (number, comma-list, A)"; then
        printf '  '; _red "Invalid choice"; echo; _pause; return
    fi

    local hook_script
    hook_script=$(cat <<'HOOK'
#!/usr/bin/env bash
# Auto-update codebase-memory-mcp index after commit
_mcp_bin="$(command -v codebase-memory-mcp 2>/dev/null)"
[[ -z "$_mcp_bin" ]] && exit 0
_repo="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$_repo" ]] && exit 0
"$_mcp_bin" cli index_repository "{\"repo_path\":\"$_repo\"}" > /dev/null 2>&1 &
HOOK
)

    echo
    for i in "${_picked[@]}"; do
        local hook_path="${_proj_paths[$i]}/.git/hooks/post-commit"
        printf '  Installing hook in '; _cyan "${_proj_labels[$i]}"; printf '... '
        if [[ -f "$hook_path" ]] && grep -q "codebase-memory-mcp" "$hook_path" 2>/dev/null; then
            _yellow "already installed"; echo
        else
            printf '%s\n' "$hook_script" > "$hook_path"
            chmod +x "$hook_path"
            _green "done"; echo
        fi
        printf '    '; _dim "$hook_path"; echo
    done
    echo; _pause
}

do_clean_stale() {
    _load_projects

    local stale_idxs=()
    for i in "${!_proj_names[@]}"; do
        [[ "${_proj_stale[$i]}" == "stale" ]] && stale_idxs+=("$i")
    done

    if (( ${#stale_idxs[@]} == 0 )); then
        echo
        printf '  '; _green "No stale entries found."; echo
        echo; _pause; return
    fi

    echo
    printf '  Stale entries:\n\n'
    for i in "${stale_idxs[@]}"; do
        printf '  • %s\n' "${_proj_labels[$i]}"
        printf '    '; _dim "${_proj_paths[$i]}"; echo
    done
    echo

    if ! _confirm "Delete all ${#stale_idxs[@]} stale entries?"; then
        printf '  '; _dim "Cancelled"; echo; echo; _pause; return
    fi

    echo
    for i in "${stale_idxs[@]}"; do
        printf '  Deleting '; _cyan "${_proj_labels[$i]}"; printf '... '
        _mcp delete_project "{\"project\":\"${_proj_names[$i]}\"}" > /dev/null
        _green "done"; echo
    done

    # Offer to re-index at projects/ equivalent
    local reindex_paths=()
    for i in "${stale_idxs[@]}"; do
        local new_path="${_proj_paths[$i]/\/workspace\//\/projects\/}"
        [[ -d "$new_path" ]] && reindex_paths+=("$new_path")
    done

    if (( ${#reindex_paths[@]} == 0 )); then
        echo; printf '  '; _green "Done."; echo
        echo; _pause; return
    fi

    echo
    printf '  Found %d projects/ equivalent(s):\n' "${#reindex_paths[@]}"
    for p in "${reindex_paths[@]}"; do printf '    %s\n' "$(basename "$p")"; done
    echo

    if _confirm "Re-index all?"; then
        echo
        for p in "${reindex_paths[@]}"; do
            _index_one "$p"
        done
    fi
    echo; _pause
}

# ── Main menu ─────────────────────────────────────────────────────────────────

main() {
    _check_mcp

    while true; do
        _print_header
        _render_projects

        printf '  '; _bold "Actions"; echo; echo
        printf '  1) Index\n'
        printf '  2) Detect changes\n'
        printf '  3) Search\n'
        printf '  4) Delete\n'
        printf '  5) Clean stale\n'
        printf '  6) Install git hooks\n'
        printf '  q) Quit\n'
        echo
        read -rp "  Choice: " choice

        case "$choice" in
            1) do_index ;;
            2) do_detect_changes ;;
            3) do_search ;;
            4) do_delete ;;
            5) do_clean_stale ;;
            6) do_install_hooks ;;
            q|Q) echo; exit 0 ;;
            *) ;;
        esac
    done
}

main "$@"
