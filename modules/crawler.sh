#!/usr/bin/env bash
# OnionRoot — modules/crawler.sh
# BFS crawler: discovers new .onion services starting from seed URLs

function mod_crawl() {
    local max_depth="${OR_DEPTH:-2}"
    local seeds_file="$ONIONROOT_HOME/data/seeds.txt"

    or_section "Onion Crawler"
    or_info "Depth: ${BOLD}${max_depth}${NC}"
    or_info "Dataset: ${BOLD}${OR_DATASET_FILE}${NC}"
    or_info "Seeds: ${BOLD}${seeds_file}${NC}"
    echo ""

    # Init queue from seeds
    if [[ ! -f "$seeds_file" ]]; then
        log_err "Seeds file not found: $seeds_file"
        exit 1
    fi

    # Reset queue, keep visited history
    : > "$OR_QUEUE_FILE"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local host
        host=$(normalize_onion_url "$line")
        queue_add "$host"
    done < "$seeds_file"

    local discovered=0
    local errors=0
    local depth=0

    or_info "Starting crawl  ${DIM}(Ctrl+C to stop and save progress)${NC}"
    echo ""

    # Trap Ctrl+C gracefully
    trap '_crawl_summary "$discovered" "$errors"; exit 0' INT TERM

    while [[ "$(queue_size)" -gt 0 && $depth -le $max_depth ]]; do

        local batch_size
        batch_size=$(queue_size)

        for (( i=0; i<batch_size; i++ )); do
            local onion
            onion=$(queue_pop)
            [[ -z "$onion" ]] && break

            if visited_has "$onion"; then
                continue
            fi
            visited_add "$onion"

            printf "  ${DIM}[→]${NC} ${DIM}Fetching:${NC} ${W}%s${NC}\r" "$onion"

            local url="http://${onion}"
            local body
            body=$(fetch_onion "$url")

            if [[ -z "$body" ]]; then
                (( errors++ )) || true
                log_debug "No response: $onion"
                polite_sleep
                continue
            fi

            # Extract page title
            local title
            title=$(echo "$body" | grep -oiP '(?<=<title>)[^<]*' | head -1 | \
                    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 120)
            [[ -z "$title" ]] && title="(no title)"

            # Get server header
            local server
            server=$(tor_headers "$url" | grep -i "^server:" | awk '{print $2}' | tr -d '\r' | head -1)
            [[ -z "$server" ]] && server="unknown"

            # Extract .onion links
            local links_raw
            links_raw=$(echo "$body" | extract_onions)

            # Save to dataset
            if ! dataset_has "$onion"; then
                local links_joined
                links_joined=$(echo "$links_raw" | tr '\n' ' ')
                dataset_save "$onion" "$title" "$server" "200" "$links_joined" "crawler"
                (( discovered++ )) || true
                printf "\033[2K"
                or_hit "${G}${BOLD}%-54s${NC}  ${DIM}%s${NC}" "$onion" "$title"
                log_info "Crawled: $onion — $title"
            fi

            # Enqueue new links for next depth
            if [[ $depth -lt $max_depth ]]; then
                while IFS= read -r linked_onion; do
                    [[ -z "$linked_onion" ]] && continue
                    queue_add "$linked_onion"
                done <<< "$links_raw"
            fi

            polite_sleep
        done

        (( depth++ )) || true
        or_info "Depth ${depth}/${max_depth} done  ${DIM}(queue: $(queue_size))${NC}"

    done

    trap - INT TERM
    _crawl_summary "$discovered" "$errors"
}

function _crawl_summary() {
    local found="$1" errs="$2"
    echo ""
    or_divider
    or_hit "Crawl complete"
    or_kv "Discovered"    "$found new services"
    or_kv "Errors"        "$errs"
    or_kv "Dataset total" "$(dataset_count) services"
    or_kv "Saved to"      "$OR_DATASET_FILE"
    or_divider
    echo ""
}
