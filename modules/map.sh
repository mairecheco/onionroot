#!/usr/bin/env bash
# OnionRoot — modules/map.sh
# Map the internal link structure of an onion service as a tree

declare -A _MAP_VISITED
declare -a _MAP_LINKS

function mod_map() {
    local target="$1"
    local host
    host=$(normalize_onion_url "$target")

    if ! is_valid_onion "$host"; then
        log_err "Invalid onion address: $target"
        exit 1
    fi

    local max_depth="${OR_DEPTH:-2}"

    or_section "Network Mapper — ${host}"
    or_info "Max depth: ${BOLD}${max_depth}${NC}"
    or_info "Routing through Tor..."
    echo ""

    _MAP_VISITED=()
    _map_crawl "$host" 0 "$max_depth" ""

    echo ""
    or_divider
    or_kv "Root"    "$host"
    or_kv "Depth"   "$max_depth"
    or_kv "Mapped"  "${#_MAP_VISITED[@]} services"
    or_divider
    echo ""
    log_info "Map complete: $host — ${#_MAP_VISITED[@]} nodes"
}

# Recursive DFS map with tree rendering
# Args: host depth max_depth prefix
function _map_crawl() {
    local host="$1"
    local depth="$2"
    local max_depth="$3"
    local prefix="$4"

    # Print current node
    if [[ $depth -eq 0 ]]; then
        printf "  ${LP}${BOLD}%s${NC}\n" "$host"
    fi

    # Already visited
    if [[ -n "${_MAP_VISITED[$host]+_}" ]]; then
        return
    fi
    _MAP_VISITED["$host"]=1

    [[ $depth -ge $max_depth ]] && return

    # Fetch links
    local url="http://${host}"
    local body
    body=$(fetch_onion "$url" 2>/dev/null || true)

    if [[ -z "$body" ]]; then
        return
    fi

    # Extract unique child onions (exclude self)
    local -a children=()
    while IFS= read -r child; do
        [[ -z "$child" || "$child" == "$host" ]] && continue
        if [[ -z "${_MAP_VISITED[$child]+_}" ]]; then
            children+=("$child")
        fi
    done < <(echo "$body" | extract_onions)

    local total=${#children[@]}
    local i=0

    for child in "${children[@]}"; do
        (( i++ )) || true
        local is_last=0
        [[ $i -eq $total ]] && is_last=1

        local connector branch_prefix
        if [[ $is_last -eq 1 ]]; then
            connector="└──"
            branch_prefix="${prefix}    "
        else
            connector="├──"
            branch_prefix="${prefix}│   "
        fi

        # Get title for the child
        local child_body child_title child_status
        child_body=$(fetch_onion "http://${child}" 2>/dev/null || true)
        child_title=$(echo "$child_body" | grep -oiP '(?<=<title>)[^<]*' | head -1 | \
                      sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 50)
        [[ -z "$child_title" ]] && child_title="(no title)"

        local depth_color
        case $depth in
            0) depth_color="$G"  ;;
            1) depth_color="$C"  ;;
            *) depth_color="$DIM";;
        esac

        printf "  ${P}%s${NC}${depth_color}%s${NC}%s  ${DIM}%s${NC}\n" \
            "${prefix}${connector}" " " "$child" "$child_title"

        # Recurse
        _map_crawl "$child" $(( depth + 1 )) "$max_depth" "$branch_prefix"

        polite_sleep
    done
}
