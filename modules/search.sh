#!/usr/bin/env bash
# OnionRoot — modules/search.sh
# Search the local onion dataset

function mod_search() {
    local keyword="$*"

    if [[ -z "$keyword" ]]; then
        log_err "Usage: onionroot search <keyword>"
        exit 1
    fi

    or_section "Search — \"${keyword}\""

    if [[ ! -f "$OR_DATASET_FILE" || ! -s "$OR_DATASET_FILE" ]]; then
        or_warn "Dataset is empty. Run ${W}onionroot crawl${NC} or ${W}onionroot dataset build${NC} first."
        echo ""
        return
    fi

    or_info "Searching ${W}$(dataset_count)${NC} entries..."
    echo ""

    local count=0
    local kw_lower
    kw_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local line_lower
        line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')

        if echo "$line_lower" | grep -qF "$kw_lower"; then
            (( count++ )) || true

            # Parse fields with Python for reliability
            local onion title source discovered
            onion=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('onion','?'))" 2>/dev/null || \
                    echo "$line" | grep -oP '(?<="onion":")[^"]*')
            title=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('title','?'))" 2>/dev/null || \
                    echo "?")
            source=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('source','?'))" 2>/dev/null || \
                    echo "?")
            discovered=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('discovered','?')[:10])" 2>/dev/null || \
                    echo "?")

            printf "  ${G}[%03d]${NC}  ${LP}%s${NC}\n" "$count" "$onion"
            printf "         ${DIM}Title:${NC}      ${W}%s${NC}\n" "${title:0:80}"
            printf "         ${DIM}Source:${NC}     ${W}%s${NC}\n" "$source"
            printf "         ${DIM}Discovered:${NC} ${W}%s${NC}\n" "$discovered"
            echo ""
        fi
    done < "$OR_DATASET_FILE"

    or_divider
    if [[ $count -eq 0 ]]; then
        or_warn "No results found for \"${keyword}\""
    else
        or_hit "${count} result(s) found for \"${keyword}\""
    fi
    or_divider
    echo ""
    log_info "Search: '$keyword' — $count results"
}
