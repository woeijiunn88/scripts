#!/bin/bash
# =============================================================================
# docker-update.sh — Stop, pull, and restart all Docker Compose services
# =============================================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DOCKER_DIR="${DOCKER_DIR:-$HOME/.docker}"
LOG_FILE="${LOG_FILE:-$HOME/.log/docker/docker-update_$(date '+%Y%m%d_%H%M%S').log}"
STOP_TIMEOUT="${STOP_TIMEOUT:-30}"       # seconds to wait before force-killing
PARALLEL="${PARALLEL:-false}"            # set to "true" to update stacks in parallel
DOCKER_COMPOSE="${DOCKER_COMPOSE:-}"     # auto-detected if empty

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local colour="$RESET"
    case "$level" in
        INFO)  colour="$GREEN"  ;;
        WARN)  colour="$YELLOW" ;;
        ERROR) colour="$RED"    ;;
        STEP)  colour="$CYAN"   ;;
    esac
    local plain; plain=$(printf "[%s] [%-5s] %s\n" "$ts" "$level" "$msg")
    local coloured; coloured=$(printf "${colour}[%s] [%-5s] %s${RESET}\n" "$ts" "$level" "$msg")
    echo "$coloured"
    echo "$plain" >> "$LOG_FILE"
}

# ── Helpers ───────────────────────────────────────────────────────────────────
require() {
    command -v "$1" &>/dev/null || { log ERROR "Required command not found: $1"; exit 1; }
}

detect_compose() {
    if [[ -n "$DOCKER_COMPOSE" ]]; then return; fi
    if docker compose version &>/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        log ERROR "Neither 'docker compose' nor 'docker-compose' is available."
        exit 1
    fi
    log INFO "Using compose command: $DOCKER_COMPOSE"
}

# ── Stop all running containers ───────────────────────────────────────────────
stop_all_containers() {
    log STEP "── Stopping all running containers ──"

    local containers
    containers=$(docker ps -q)

    if [[ -z "$containers" ]]; then
        log INFO "No running containers found."
        return
    fi

    local count; count=$(echo "$containers" | wc -l | tr -d ' ')
    log INFO "Found $count running container(s)."

    # Stop with a timeout, then force-remove stragglers
    # shellcheck disable=SC2086
    docker stop --timeout="$STOP_TIMEOUT" $containers && \
        log INFO "All containers stopped cleanly." || \
        log WARN "Some containers did not stop cleanly; they may have been force-killed."
}

# ── Update a single Compose stack ─────────────────────────────────────────────
update_stack() {
    local file="$1"
    local dir; dir=$(dirname "$file")
    local stack_name; stack_name=$(basename "$dir")

    log STEP "── Stack: $stack_name ($file) ──"

    # Validate the compose file before doing anything destructive
    if ! $DOCKER_COMPOSE -f "$file" config --quiet >> "$LOG_FILE" 2>&1; then
        log ERROR "[$stack_name] Invalid compose file — skipping."
        return 1
    fi

    # Bring the stack down
    log INFO "[$stack_name] Bringing stack down..."
    if ! $DOCKER_COMPOSE --progress quiet -f "$file" down --remove-orphans >> "$LOG_FILE" 2>&1; then
        log ERROR "[$stack_name] 'down' failed — skipping pull & up."
        return 1
    fi

    # Pull latest images; capture exit code without aborting the whole script
    log INFO "[$stack_name] Pulling latest images..."
    if ! $DOCKER_COMPOSE --progress quiet -f "$file" pull >> "$LOG_FILE" 2>&1; then
        log WARN "[$stack_name] 'pull' encountered errors; continuing with local images."
    fi

    # Start the stack
    log INFO "[$stack_name] Starting stack..."
    if ! $DOCKER_COMPOSE --progress quiet -f "$file" up -d --remove-orphans >> "$LOG_FILE" 2>&1; then
        log ERROR "[$stack_name] 'up' failed."
        return 1
    fi

    log INFO "[$stack_name] ✓ Updated successfully."
}

# ── Discover and process all stacks ──────────────────────────────────────────
update_all_stacks() {
    log STEP "── Discovering Compose files in $DOCKER_DIR ──"

    # Collect all yml/yaml files at depth 2 (one level of subdirectories)
    local -a files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$DOCKER_DIR" -mindepth 2 -maxdepth 2 \
                  \( -name "*.yml" -o -name "*.yaml" \) \
                  -type f -print0 2>/dev/null)

    if [[ ${#files[@]} -eq 0 ]]; then
        log WARN "No Compose files found under $DOCKER_DIR — nothing to update."
        return
    fi

    log INFO "Found ${#files[@]} Compose file(s)."

    local failed=0

    if [[ "$PARALLEL" == "true" ]]; then
        log INFO "Running stack updates in parallel..."
        local pids=()
        for f in "${files[@]}"; do
            update_stack "$f" &
            pids+=($!)
        done
        for pid in "${pids[@]}"; do
            wait "$pid" || (( failed++ )) || true
        done
    else
        for f in "${files[@]}"; do
            update_stack "$f" || (( failed++ )) || true
        done
    fi

    if (( failed > 0 )); then
        log WARN "$failed stack(s) encountered errors. Check $LOG_FILE for details."
    else
        log INFO "All stacks updated successfully."
    fi
}

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    local code=$?
    if (( code != 0 )); then
        log ERROR "Script exited with code $code. Check $LOG_FILE for details."
    fi
}
trap cleanup EXIT

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    # Ensure log file is writable (create if needed)
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/docker-update.log"

    log INFO "════════════════════════════════════════"
    log INFO " Docker Update Script started"
    log INFO " Log: $LOG_FILE"
    log INFO "════════════════════════════════════════"

    require docker
    detect_compose

    stop_all_containers
    sleep 2
    update_all_stacks

    log INFO "════════════════════════════════════════"
    log INFO " Done."
    log INFO "════════════════════════════════════════"
}

main "$@"