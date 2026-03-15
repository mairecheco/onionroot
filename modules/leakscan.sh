#!/usr/bin/env bash
# OnionRoot — modules/leakscan.sh
# Detect information leaks that could de-anonymize an onion service

function mod_leakscan() {
    local target="$1"
    local host
    host=$(normalize_onion_url "$target")

    if ! is_valid_onion "$host"; then
        log_err "Invalid onion address: $target"
        exit 1
    fi

    local url="http://${host}"
    local leak_count=0

    or_section "Leak Scanner — ${host}"
    or_info "Fetching page content through Tor..."
    echo ""

    local body headers
    body=$(fetch_onion "$url" 2>/dev/null || true)
    headers=$(tor_headers "$url" 2>/dev/null || true)

    if [[ -z "$body" && -z "$headers" ]]; then
        or_warn "No response — service may be offline"
        return
    fi

    local combined="${body}${headers}"

    # ── External clearnet resources ────────────────────────────────────────────
    or_section "External Clearnet Requests"
    or_info "Checking for links to clearnet domains..."

    local clearnet_found=0
    local -a CLEARNET_SIGS=(
        "google-analytics.com"
        "googletagmanager.com"
        "cloudflare.com"
        "cdn.jsdelivr.net"
        "cdnjs.cloudflare.com"
        "ajax.googleapis.com"
        "fonts.googleapis.com"
        "facebook.com"
        "twitter.com"
        "doubleclick.net"
        "amazon.com"
        "amazonaws.com"
        "akamaihd.net"
        "fastly.net"
        "stackpath.bootstrapcdn.com"
    )

    for domain in "${CLEARNET_SIGS[@]}"; do
        if echo "$combined" | grep -qi "$domain"; then
            printf "  ${R}[LEAK]${NC}  ${Y}External clearnet resource:${NC}  ${W}%s${NC}\n" "$domain"
            (( leak_count++ )) || true
            (( clearnet_found++ )) || true
            log_warn "Clearnet leak: $domain in $host"
        fi
    done
    [[ $clearnet_found -eq 0 ]] && or_hit "No known clearnet CDN/tracker references found"

    # ── Inline IP addresses ────────────────────────────────────────────────────
    or_section "Inline IP Addresses"
    or_info "Scanning for hardcoded IP addresses..."

    local ips
    ips=$(echo "$combined" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
        | grep -vE '^(127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' \
        | grep -vE '^255\.' \
        | sort -u)

    if [[ -n "$ips" ]]; then
        while IFS= read -r ip; do
            printf "  ${R}[LEAK]${NC}  ${Y}Possible IP exposure:${NC}  ${W}%s${NC}\n" "$ip"
            (( leak_count++ )) || true
            log_warn "IP leak: $ip in $host"
        done <<< "$ips"
    else
        or_hit "No public IP addresses found in page content"
    fi

    # ── Email addresses ────────────────────────────────────────────────────────
    or_section "Email Addresses"
    local emails
    emails=$(echo "$combined" | grep -oiE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
        | sort -u | head -20)

    if [[ -n "$emails" ]]; then
        while IFS= read -r email; do
            printf "  ${Y}[INFO]${NC}  ${W}%s${NC}\n" "$email"
            log_info "Email found: $email in $host"
        done <<< "$emails"
        or_warn "Email addresses found — may expose identity"
        (( leak_count++ )) || true
    else
        or_hit "No email addresses found"
    fi

    # ── Server version disclosure ──────────────────────────────────────────────
    or_section "Server Version Disclosure"
    local server_header
    server_header=$(echo "$headers" | grep -i "^server:" | tr -d '\r')
    if echo "$server_header" | grep -qiE "[0-9]+\.[0-9]+"; then
        printf "  ${Y}[WARN]${NC}  ${Y}Server version disclosed:${NC}  ${W}%s${NC}\n" "$server_header"
        or_warn "Exposing server version aids fingerprinting"
        (( leak_count++ )) || true
    else
        or_hit "Server header does not disclose version"
    fi

    local xpowered
    xpowered=$(echo "$headers" | grep -i "^x-powered-by:" | tr -d '\r')
    if [[ -n "$xpowered" ]]; then
        printf "  ${Y}[WARN]${NC}  ${Y}X-Powered-By disclosed:${NC}  ${W}%s${NC}\n" "$xpowered"
        (( leak_count++ )) || true
    fi

    # ── Cookie security ────────────────────────────────────────────────────────
    or_section "Cookie Security"
    local cookies
    cookies=$(echo "$headers" | grep -i "^set-cookie:" | tr -d '\r')
    if [[ -n "$cookies" ]]; then
        local cookie_issues=0
        while IFS= read -r cookie; do
            printf "  ${DIM}  Cookie: %s${NC}\n" "${cookie:0:100}"
            if ! echo "$cookie" | grep -qi "HttpOnly"; then
                or_warn "Missing HttpOnly flag"
                (( cookie_issues++ )) || true
            fi
            if ! echo "$cookie" | grep -qi "SameSite"; then
                or_warn "Missing SameSite attribute"
                (( cookie_issues++ )) || true
            fi
        done <<< "$cookies"
        [[ $cookie_issues -gt 0 ]] && (( leak_count++ )) || true
    else
        or_info "No cookies set"
    fi

    # ── Directory listing ──────────────────────────────────────────────────────
    or_section "Directory Listing / Sensitive Paths"
    local -a SENSITIVE_PATHS=(".git/" ".env" "phpinfo.php" "wp-config.php"
        "config.php" "admin/" "backup/" ".htaccess" "server-status" "robots.txt")
    local exposed=0
    for path in "${SENSITIVE_PATHS[@]}"; do
        local pstatus
        pstatus=$(tor_status_code "${url}/${path}" 2>/dev/null || echo "000")
        if [[ "$pstatus" == "200" || "$pstatus" == "301" || "$pstatus" == "302" ]]; then
            printf "  ${R}[LEAK]${NC}  ${Y}Accessible:${NC}  ${W}%s${NC}  ${DIM}[HTTP %s]${NC}\n" \
                "${url}/${path}" "$pstatus"
            (( leak_count++ )) || true
            (( exposed++ )) || true
            log_warn "Exposed path: $path on $host"
        fi
        sleep 0.5
    done
    [[ $exposed -eq 0 ]] && or_hit "No sensitive paths exposed"

    # ── Clearnet onion-agnostic refs ───────────────────────────────────────────
    or_section "Security Headers Audit"
    declare -A SEC_HEADERS=(
        ["content-security-policy"]="Content-Security-Policy"
        ["x-frame-options"]="X-Frame-Options"
        ["x-content-type-options"]="X-Content-Type-Options"
        ["strict-transport-security"]="Strict-Transport-Security"
        ["referrer-policy"]="Referrer-Policy"
    )
    for key in "${!SEC_HEADERS[@]}"; do
        local label="${SEC_HEADERS[$key]}"
        if echo "$headers" | grep -qi "^${key}:"; then
            printf "  ${G}[OK]${NC}  ${DIM}%s set${NC}\n" "$label"
        else
            printf "  ${Y}[MISSING]${NC}  ${W}%s${NC}\n" "$label"
        fi
    done

    # ── Summary ────────────────────────────────────────────────────────────────
    echo ""
    or_divider
    or_kv "Target"  "$host"
    if [[ $leak_count -eq 0 ]]; then
        or_hit "No critical leaks detected"
    else
        printf "  ${R}[!]${NC}  ${BOLD}%d potential leak(s) detected${NC}\n" "$leak_count"
    fi
    or_kv "Issues" "$leak_count"
    or_divider
    echo ""
    log_info "Leakscan complete: $host — $leak_count issues"
}
