#!/usr/bin/env bash
# OnionRoot — modules/scanner.sh
# Port and service scanning via Tor.
# Root mode:     torsocks + nmap (SYN scan, OS detection, full service scan)
# Rootless mode: torsocks + nmap -sT (connect scan) or curl SOCKS5 probes

# Common ports to probe
declare -A OR_COMMON_PORTS=(
    ["21"]="ftp"
    ["22"]="ssh"
    ["23"]="telnet"
    ["25"]="smtp"
    ["53"]="dns"
    ["80"]="http"
    ["110"]="pop3"
    ["143"]="imap"
    ["443"]="https"
    ["587"]="smtp-submission"
    ["993"]="imaps"
    ["995"]="pop3s"
    ["3306"]="mysql"
    ["5432"]="postgresql"
    ["6667"]="irc"
    ["8080"]="http-alt"
    ["8443"]="https-alt"
    ["8888"]="http-alt2"
)

function mod_scan() {
    local target="$1"
    local host
    host=$(normalize_onion_url "$target")

    if ! is_valid_onion "$host"; then
        log_err "Invalid onion address: $target"
        exit 1
    fi

    or_section "Onion Scanner — ${host}"

    # Show mode badge
    if [[ "$OR_MODE" == "root" ]]; then
        printf "  ${G}  Mode: ROOT${NC}  ${DIM}— SYN scan, OS detection, service fingerprint${NC}\n\n"
    else
        printf "  ${Y}  Mode: ROOTLESS${NC}  ${DIM}— TCP connect scan, no raw sockets${NC}\n"
        printf "  ${DIM}  Tip: run with sudo for deeper scanning${NC}\n\n"
    fi

    or_info "Target:  ${W}${host}${NC}"
    or_info "Proxy:   ${W}${OR_TOR_HOST}:${OR_TOR_PORT}${NC}"
    or_warn "Scanning onion services is slow. Be patient."
    echo ""

    local open_count=0
    local port_list
    port_list=$(IFS=,; echo "${!OR_COMMON_PORTS[*]}" | tr ' ' ',')

    # ── ROOT MODE ──────────────────────────────────────────────────────────────
    if [[ "$OR_MODE" == "root" ]]; then
        _scan_root "$host" "$port_list"
        open_count=$?

    # ── ROOTLESS MODE ──────────────────────────────────────────────────────────
    else
        _scan_rootless "$host" "$port_list"
        open_count=$?
    fi

    # ── Summary ────────────────────────────────────────────────────────────────
    echo ""
    or_divider
    or_kv "Target"     "$host"
    or_kv "Mode"       "$OR_MODE"
    or_kv "Open ports" "$open_count"
    or_divider
    echo ""
    log_info "Scan complete: $host — mode=$OR_MODE open=$open_count"

    # return 0 regardless (open_count was tracked via stdout, not exit code)
    return 0
}

# ── Root scan: torsocks + nmap SYN + service detection ────────────────────────
function _scan_root() {
    local host="$1"
    local port_list="$2"
    local count=0

    or_section "Port Scan (Root — SYN + Service)"

    if [[ $OR_CAN_TORSOCKS -eq 0 || $OR_CAN_NMAP -eq 0 ]]; then
        or_warn "torsocks or nmap not found — falling back to rootless mode"
        _scan_rootless "$host" "$port_list"
        return $?
    fi

    or_info "Running: ${DIM}torsocks nmap -sS -sV -O --open${NC}"
    echo ""

    local nmap_out
    nmap_out=$(torsocks nmap \
        -sS -sV -O \
        --open \
        -p "$port_list" \
        --host-timeout 180s \
        --script-timeout 30s \
        -Pn \
        "$host" 2>/dev/null || true)

    # Print open ports with service info
    echo "$nmap_out" | grep -E "^[0-9]+/tcp" | while IFS= read -r line; do
        local port state service version
        port=$(echo    "$line" | awk '{print $1}')
        state=$(echo   "$line" | awk '{print $2}')
        service=$(echo "$line" | awk '{print $3}')
        version=$(echo "$line" | cut -d' ' -f4- | sed 's/^[[:space:]]*//')
        if [[ "$state" == "open" ]]; then
            printf "  ${G}[OPEN]${NC}  ${W}%-10s${NC}  ${C}%-14s${NC}  ${DIM}%s${NC}\n" \
                "$port" "$service" "${version:0:50}"
            (( count++ )) || true
        fi
    done

    # OS detection result
    local os_guess
    os_guess=$(echo "$nmap_out" | grep -i "OS details\|Running:" | head -2)
    if [[ -n "$os_guess" ]]; then
        echo ""
        or_section "OS Detection"
        echo "$os_guess" | while IFS= read -r l; do
            printf "  ${DIM}  %s${NC}\n" "$l"
        done
    fi

    # NSE script results
    local scripts
    scripts=$(echo "$nmap_out" | grep -A2 "^|" | head -30)
    if [[ -n "$scripts" ]]; then
        echo ""
        or_section "Service Scripts"
        echo "$scripts" | while IFS= read -r l; do
            printf "  ${DIM}  %s${NC}\n" "$l"
        done
    fi

    return $count
}

# ── Rootless scan: torsocks + nmap -sT (connect) or curl SOCKS5 probes ────────
function _scan_rootless() {
    local host="$1"
    local port_list="$2"
    local count=0

    or_section "Port Scan (Rootless — TCP Connect)"

    if [[ $OR_CAN_TORSOCKS -eq 1 && $OR_CAN_NMAP -eq 1 ]]; then
        # Best rootless option: torsocks + nmap connect scan
        or_info "Running: ${DIM}torsocks nmap -sT --open${NC}"
        echo ""

        torsocks nmap \
            -sT \
            --open \
            -p "$port_list" \
            --host-timeout 180s \
            -Pn \
            "$host" 2>/dev/null \
        | grep -E "^[0-9]+/tcp" | while IFS= read -r line; do
            local port state service
            port=$(echo    "$line" | awk '{print $1}')
            state=$(echo   "$line" | awk '{print $2}')
            service=$(echo "$line" | awk '{print $3}')
            if [[ "$state" == "open" ]]; then
                printf "  ${G}[OPEN]${NC}  ${W}%-10s${NC}  ${C}%s${NC}\n" "$port" "$service"
                (( count++ )) || true
            fi
        done

    else
        # Fallback: pure curl SOCKS5 probes — no nmap needed
        or_info "Using curl SOCKS5 probes (torsocks/nmap not found)"
        or_info "Install torsocks + nmap for better results"
        echo ""

        for port in "${!OR_COMMON_PORTS[@]}"; do
            local svc="${OR_COMMON_PORTS[$port]}"
            local status

            status=$(curl \
                --socks5-hostname "${OR_TOR_HOST}:${OR_TOR_PORT}" \
                -A "$OR_USER_AGENT" \
                --connect-timeout 8 \
                --max-time 12 \
                -s -o /dev/null -w "%{http_code}" \
                "http://${host}:${port}/" 2>/dev/null || echo "000")

            if [[ "$status" != "000" ]]; then
                printf "  ${G}[OPEN]${NC}  ${W}%-10s${NC}  ${C}%-14s${NC}  ${DIM}HTTP %s${NC}\n" \
                    "${port}/tcp" "$svc" "$status"
                (( count++ )) || true
            else
                printf "  ${DIM}[----]  %-10s  %s${NC}\n" "${port}/tcp" "$svc"
            fi
            sleep 1
        done
    fi

    # HTTP banner grab for any open web ports
    if [[ $count -gt 0 ]]; then
        echo ""
        or_section "HTTP Banner Grab"
        for port in 80 443 8080 8443 8888; do
            local status
            status=$(tor_status_code "http://${host}:${port}" 2>/dev/null || echo "000")
            if [[ "$status" != "000" ]]; then
                local server
                server=$(tor_headers "http://${host}:${port}" 2>/dev/null \
                    | grep -i "^server:" | awk '{print $2}' | tr -d '\r' | head -1)
                printf "  ${G}[%s]${NC}  ${W}%-6s${NC}  ${DIM}server: %s${NC}\n" \
                    "$status" ":${port}" "${server:-unknown}"
            fi
        done
    fi

    return $count
}
