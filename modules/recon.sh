#!/usr/bin/env bash
# OnionRoot — modules/recon.sh
# Gather intelligence on a single .onion service

function mod_recon() {
    local target="$1"
    local host
    host=$(normalize_onion_url "$target")

    if ! is_valid_onion "$host"; then
        log_err "Invalid onion address: $target"
        exit 1
    fi

    local url="http://${host}"

    or_section "Onion Recon — ${host}"
    or_info "Routing through Tor (${OR_TOR_HOST}:${OR_TOR_PORT})"
    echo ""

    # ── Fetch body + headers ───────────────────────────────────────────────────
    or_info "Fetching ${W}${url}${NC} ..."
    local headers body status_code
    headers=$(tor_headers "$url" 2>/dev/null || true)
    body=$(fetch_onion "$url" 2>/dev/null || true)
    status_code=$(tor_status_code "$url" 2>/dev/null || echo "000")

    if [[ -z "$body" && -z "$headers" ]]; then
        or_warn "No response from ${host}. Service may be offline or slow."
        echo ""
        return
    fi

    # ── Basic Info ─────────────────────────────────────────────────────────────
    or_section "Basic Info"
    or_kv "Domain"   "$host"
    or_kv "URL"      "$url"
    or_kv "Status"   "$status_code"

    local title
    title=$(echo "$body" | grep -oiP '(?<=<title>)[^<]*' | head -1 | \
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -n "$title" ]] && or_kv "Page Title" "$title"

    # ── Server Headers ─────────────────────────────────────────────────────────
    or_section "Server Headers"
    local interesting_headers=(
        "server" "x-powered-by" "content-type" "set-cookie"
        "x-frame-options" "content-security-policy" "strict-transport-security"
        "x-content-type-options" "location" "via" "x-generator"
    )
    local found_any=0
    for h in "${interesting_headers[@]}"; do
        local val
        val=$(echo "$headers" | grep -i "^${h}:" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
        if [[ -n "$val" ]]; then
            or_kv "$h" "$val"
            found_any=1
        fi
    done
    [[ $found_any -eq 0 ]] && or_info "No notable headers found"

    # ── Technology Detection ───────────────────────────────────────────────────
    or_section "Technology Fingerprint"
    local combined="${body}${headers}"
    local found_tech=0

    declare -A TECHS=(
        ["PHP"]="X-Powered-By: PHP|\.php[\?\"']"
        ["Python/Flask"]="Werkzeug|Flask"
        ["Python/Django"]="csrfmiddlewaretoken|django"
        ["Ruby on Rails"]="X-Powered-By: Phusion Passenger|_rails_session"
        ["Node.js/Express"]="X-Powered-By: Express"
        ["Nginx"]="Server: nginx"
        ["Apache"]="Server: Apache"
        ["WordPress"]="wp-content|wp-includes"
        ["Drupal"]="drupal|sites/default"
        ["Joomla"]="joomla|/components/com_"
        ["jQuery"]="jquery"
        ["React"]="react-root|__NEXT_DATA__|_reactRootContainer"
        ["Bootstrap"]="bootstrap"
        ["Tor2Web"]="tor2web"
        ["OnionShare"]="onionshare"
    )

    for tech in "${!TECHS[@]}"; do
        if echo "$combined" | grep -qiE "${TECHS[$tech]}"; then
            printf "  ${G}  ✓${NC}  ${W}%s${NC}\n" "$tech"
            (( found_tech++ )) || true
        fi
    done
    [[ $found_tech -eq 0 ]] && or_info "No common frameworks detected"

    # ── Meta Tags ──────────────────────────────────────────────────────────────
    local meta_desc
    meta_desc=$(echo "$body" | grep -oiP '(?<=content=")[^"]*(?="[^>]*name="description")' | head -1)
    if [[ -z "$meta_desc" ]]; then
        meta_desc=$(echo "$body" | grep -oiP '(?i)(?<=<meta name="description" content=")[^"]*' | head -1)
    fi
    if [[ -n "$meta_desc" ]]; then
        or_section "Meta Description"
        printf "  ${DIM}  %s${NC}\n" "${meta_desc:0:200}"
    fi

    # ── Internal Links ─────────────────────────────────────────────────────────
    or_section "Discovered .onion Links"
    local onion_links
    onion_links=$(echo "$body" | extract_onions | grep -v "^${host}$")
    if [[ -n "$onion_links" ]]; then
        local count=0
        while IFS= read -r link; do
            printf "  ${P}  ▸${NC}  ${W}%s${NC}\n" "$link"
            (( count++ )) || true
            [[ $count -ge 20 ]] && { or_info "... and more (use 'onionroot map' for full tree)"; break; }
        done <<< "$onion_links"
    else
        or_info "No external .onion links found"
    fi

    # ── Forms detection ────────────────────────────────────────────────────────
    local form_count
    form_count=$(echo "$body" | grep -icE "<form" || echo "0")
    if [[ "$form_count" -gt 0 ]]; then
        or_section "Forms"
        or_warn "${form_count} form(s) detected — may handle user input/login"
        echo "$body" | grep -iE "<form[^>]*>" | head -5 | while IFS= read -r l; do
            printf "  ${DIM}  %s${NC}\n" "${l:0:120}"
        done
    fi

    # ── Save to dataset ─────────────────────────────────────────────────────────
    if ! dataset_has "$host"; then
        local links_joined
        links_joined=$(echo "$onion_links" | tr '\n' ' ')
        local server
        server=$(echo "$headers" | grep -i "^server:" | awk '{print $2}' | tr -d '\r' | head -1)
        dataset_save "$host" "${title:-unknown}" "${server:-unknown}" "$status_code" "$links_joined" "recon"
        or_info "Saved to dataset"
    fi

    echo ""
    or_divider
    log_info "Recon complete: $host"
}
