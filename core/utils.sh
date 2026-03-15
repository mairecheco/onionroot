#!/usr/bin/env bash
# OnionRoot — core/utils.sh
# Shared utility functions

#########################################################################
# Tor / Network
#########################################################################

# Check Tor is reachable before any onion operation
function check_tor() {
    or_info "Checking Tor connection (${OR_TOR_HOST}:${OR_TOR_PORT})..."
    local TEST
    TEST=$(curl -fsSL --socks5-hostname "${OR_TOR_HOST}:${OR_TOR_PORT}" \
        --connect-timeout 10 --max-time 20 \
        "https://check.torproject.org/api/ip" 2>/dev/null || true)
    if echo "$TEST" | grep -q '"IsTor":true'; then
        local EXIT_IP
        EXIT_IP=$(echo "$TEST" | grep -oP '"IP":"[^"]*"' | cut -d'"' -f4)
        or_hit "Tor is running  ${DIM}(exit: ${EXIT_IP})${NC}"
        log_info "Tor OK — exit IP: $EXIT_IP"
    else
        or_warn "Could not verify Tor. Ensure Tor is running on ${OR_TOR_HOST}:${OR_TOR_PORT}"
        or_info "Start Tor:  ${W}sudo systemctl start tor${NC}  or  ${W}tor &${NC}"
        log_warn "Tor check failed"
        # Don't exit — allow user to proceed if they know what they're doing
    fi
    echo ""
}

# Route HTTP through Tor SOCKS5. Always use --socks5-hostname to prevent DNS leaks.
function tor_curl() {
    curl \
        --socks5-hostname "${OR_TOR_HOST}:${OR_TOR_PORT}" \
        -A "$OR_USER_AGENT" \
        --connect-timeout "$OR_CONNECT_TIMEOUT" \
        --max-time "$OR_MAX_TIME" \
        --retry "$OR_RETRY" \
        --retry-delay 3 \
        -s \
        -L \
        "$@"
}

# Fetch page silently, return body on stdout
function fetch_onion() {
    local url="$1"
    tor_curl -f "$url" 2>/dev/null || true
}

# Extract all .onion links from HTML/text
function extract_onions() {
    grep -oiE "$OR_ONION_REGEX" \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u
}

# Rate limit between requests
function polite_sleep() {
    sleep "${OR_RATE_LIMIT}" 2>/dev/null || true
}

# Get HTTP status code through Tor
function tor_status_code() {
    local url="$1"
    curl \
        --socks5-hostname "${OR_TOR_HOST}:${OR_TOR_PORT}" \
        -A "$OR_USER_AGENT" \
        --connect-timeout "$OR_CONNECT_TIMEOUT" \
        --max-time "$OR_MAX_TIME" \
        -s -o /dev/null -w "%{http_code}" \
        -L "$url" 2>/dev/null || echo "000"
}

# Get response headers through Tor
function tor_headers() {
    local url="$1"
    curl \
        --socks5-hostname "${OR_TOR_HOST}:${OR_TOR_PORT}" \
        -A "$OR_USER_AGENT" \
        --connect-timeout "$OR_CONNECT_TIMEOUT" \
        --max-time "$OR_MAX_TIME" \
        -s -I -L "$url" 2>/dev/null || true
}

#########################################################################
# Python check
#########################################################################

function check_python() {
    if ! command -v python3 &>/dev/null; then
        log_err "python3 is required for this command. Install with: sudo apt install python3"
        exit 1
    fi
}

#########################################################################
# Dataset I/O (JSONL — one JSON object per line)
#########################################################################

# Save a discovered onion service to the dataset
# Args: onion title server status links(space-separated) source
function dataset_save() {
    local onion="$1"
    local title="${2:-unknown}"
    local server="${3:-unknown}"
    local status="${4:-0}"
    local links="${5:-}"
    local source="${6:-manual}"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    # Build links JSON array
    local links_json="[]"
    if [[ -n "$links" ]]; then
        links_json="[$(echo "$links" | tr ' ' '\n' | grep -E "$OR_ONION_REGEX" \
            | awk '{printf "\"%s\",",$0}' | sed 's/,$//')]"
    fi

    local entry
    entry=$(printf '{"onion":"%s","title":"%s","server":"%s","status":%s,"links":%s,"source":"%s","discovered":"%s"}' \
        "$onion" \
        "$(echo "$title" | tr '"' "'" | head -c 120)" \
        "$(echo "$server" | tr '"' "'" | head -c 60)" \
        "$status" \
        "$links_json" \
        "$source" \
        "$timestamp")

    echo "$entry" >> "$OR_DATASET_FILE"
    log_info "Saved: $onion"
}

# Check if an onion is already in the dataset
function dataset_has() {
    local onion="$1"
    grep -qF "\"onion\":\"${onion}\"" "$OR_DATASET_FILE" 2>/dev/null
}

# Count entries in dataset
function dataset_count() {
    if [[ -f "$OR_DATASET_FILE" ]]; then
        wc -l < "$OR_DATASET_FILE"
    else
        echo "0"
    fi
}

#########################################################################
# Visited / Queue management
#########################################################################

function visited_add() {
    echo "$1" >> "$OR_VISITED_FILE"
}

function visited_has() {
    grep -qxF "$1" "$OR_VISITED_FILE" 2>/dev/null
}

function queue_add() {
    local item="$1"
    if ! visited_has "$item" && ! grep -qxF "$item" "$OR_QUEUE_FILE" 2>/dev/null; then
        echo "$item" >> "$OR_QUEUE_FILE"
    fi
}

function queue_pop() {
    local item
    item=$(head -1 "$OR_QUEUE_FILE" 2>/dev/null || true)
    if [[ -n "$item" ]]; then
        # Remove first line
        local tmp
        tmp=$(mktemp)
        tail -n +2 "$OR_QUEUE_FILE" > "$tmp" && mv "$tmp" "$OR_QUEUE_FILE"
        echo "$item"
    fi
}

function queue_size() {
    if [[ -f "$OR_QUEUE_FILE" ]]; then
        wc -l < "$OR_QUEUE_FILE"
    else
        echo "0"
    fi
}

#########################################################################
# Misc
#########################################################################

function normalize_onion_url() {
    local input="$1"
    # Strip protocol, path — keep just host
    local host
    host=$(echo "$input" | sed 's|https\?://||;s|/.*||' | tr '[:upper:]' '[:lower:]')
    echo "$host"
}

function is_valid_onion() {
    local onion="$1"
    echo "$onion" | grep -qiE "^${OR_ONION_REGEX}$"
}
