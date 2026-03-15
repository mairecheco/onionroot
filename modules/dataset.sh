#!/usr/bin/env bash
# OnionRoot — modules/dataset.sh
# Build, inspect, and export the onion services dataset

function mod_dataset() {
    local subcmd="${1:-build}"

    case "$subcmd" in
        build)  _dataset_build ;;
        stats)  _dataset_stats ;;
        list)   _dataset_list ;;
        export) _dataset_export "${2:-}" ;;
        clear)  _dataset_clear ;;
        *)
            or_err "Unknown dataset command: $subcmd"
            printf "  Usage: ${C}onionroot dataset ${W}<build|stats|list|export|clear>${NC}\n\n"
            exit 1
            ;;
    esac
}

function _dataset_build() {
    or_section "Dataset Builder"
    or_info "Building dataset by crawling seeds..."
    echo ""

    check_tor

    local seeds_file="$ONIONROOT_HOME/data/seeds.txt"
    [[ ! -f "$seeds_file" ]] && { log_err "Seeds file not found: $seeds_file"; exit 1; }

    local added=0
    local errors=0

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local host
        host=$(normalize_onion_url "$line")

        if dataset_has "$host"; then
            or_info "${DIM}Already in dataset: ${host}${NC}"
            continue
        fi

        printf "  ${DIM}[→]${NC} ${W}%s${NC}\r" "$host"
        local url="http://${host}"
        local body headers title server status links_joined

        body=$(fetch_onion "$url" 2>/dev/null || true)
        headers=$(tor_headers "$url" 2>/dev/null || true)
        status=$(tor_status_code "$url" 2>/dev/null || echo "000")

        if [[ -z "$body" ]]; then
            (( errors++ )) || true
            polite_sleep
            continue
        fi

        title=$(echo "$body" | grep -oiP '(?<=<title>)[^<]*' | head -1 | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 120)
        server=$(echo "$headers" | grep -i "^server:" | awk '{print $2}' | tr -d '\r' | head -1)
        links_joined=$(echo "$body" | extract_onions | tr '\n' ' ')

        dataset_save "$host" "${title:-unknown}" "${server:-unknown}" "$status" "$links_joined" "build"
        (( added++ )) || true

        printf "\033[2K"
        or_hit "%-56s  ${DIM}%s${NC}" "$host" "${title:0:40}"

        polite_sleep
    done < "$seeds_file"

    echo ""
    or_divider
    or_kv "Added"         "$added new services"
    or_kv "Errors"        "$errors"
    or_kv "Dataset total" "$(dataset_count) services"
    or_kv "File"          "$OR_DATASET_FILE"
    or_divider
    echo ""
    log_info "Dataset build complete: $added added, $errors errors"
}

function _dataset_stats() {
    or_section "Dataset Statistics"

    if [[ ! -f "$OR_DATASET_FILE" || ! -s "$OR_DATASET_FILE" ]]; then
        or_warn "Dataset is empty. Run ${W}onionroot dataset build${NC} first."
        return
    fi

    python3 - "$OR_DATASET_FILE" <<'PYEOF'
import sys, json, collections

path = sys.argv[1]
entries = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pass

total = len(entries)
servers  = collections.Counter(e.get('server','unknown') for e in entries)
sources  = collections.Counter(e.get('source','unknown') for e in entries)
statuses = collections.Counter(str(e.get('status','?')) for e in entries)
total_links = sum(len(e.get('links',[])) for e in entries)

P  = '\033[0m\033[35m'
LP = '\033[0m\033[1m\033[35m'
G  = '\033[0m\033[32m'
W  = '\033[0m\033[37m'
DIM= '\033[2m'
NC = '\033[0m'

def kv(k, v): print(f"  {DIM}  {k:<20}{NC}{W}{v}{NC}")

kv("Total services",   str(total))
kv("Total links",      str(total_links))
kv("Unique servers",   str(len(servers)))
print()

print(f"  {LP}  Top Servers{NC}")
for s, c in servers.most_common(5):
    print(f"  {G}  ▸{NC}  {W}{s:<20}{NC}{DIM}{c}{NC}")

print()
print(f"  {LP}  Sources{NC}")
for s, c in sources.most_common():
    print(f"  {G}  ▸{NC}  {W}{s:<20}{NC}{DIM}{c}{NC}")

print()
print(f"  {LP}  HTTP Status Codes{NC}")
for s, c in statuses.most_common():
    print(f"  {G}  ▸{NC}  {W}{s:<20}{NC}{DIM}{c}{NC}")
PYEOF
    echo ""
    log_info "Dataset stats viewed"
}

function _dataset_list() {
    or_section "Dataset — All Entries"

    if [[ ! -f "$OR_DATASET_FILE" || ! -s "$OR_DATASET_FILE" ]]; then
        or_warn "Dataset is empty."
        return
    fi

    local i=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        (( i++ )) || true
        local onion title
        onion=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('onion','?'))" 2>/dev/null || echo "?")
        title=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('title','?'))" 2>/dev/null || echo "?")
        printf "  ${DIM}[%04d]${NC}  ${LP}%-58s${NC}  ${DIM}%s${NC}\n" "$i" "$onion" "${title:0:40}"
    done < "$OR_DATASET_FILE"

    echo ""
    or_info "Total: ${BOLD}$(dataset_count)${NC} services"
    echo ""
}

function _dataset_export() {
    local fmt="${1:-json}"
    local outfile="${OR_OUTPUT_FILE:-${OR_DATA_DIR}/export_$(date +%Y%m%d_%H%M%S).${fmt}}"

    or_section "Dataset Export — ${fmt^^}"

    if [[ ! -f "$OR_DATASET_FILE" || ! -s "$OR_DATASET_FILE" ]]; then
        or_warn "Dataset is empty."
        return
    fi

    case "$fmt" in
        json)
            python3 - "$OR_DATASET_FILE" "$outfile" <<'PYEOF'
import sys, json
entries = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            try: entries.append(json.loads(line))
            except: pass
with open(sys.argv[2], 'w') as f:
    json.dump(entries, f, indent=2)
print(len(entries))
PYEOF
            ;;
        csv)
            python3 - "$OR_DATASET_FILE" "$outfile" <<'PYEOF'
import sys, json, csv
entries = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            try: entries.append(json.loads(line))
            except: pass
fields = ['onion','title','server','status','source','discovered']
with open(sys.argv[2], 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
    w.writeheader()
    w.writerows(entries)
print(len(entries))
PYEOF
            ;;
        *)
            log_err "Supported formats: json, csv"
            exit 1
            ;;
    esac

    or_hit "Exported to: ${outfile}"
    or_kv "Format" "$fmt"
    or_kv "Total"  "$(dataset_count) services"
    echo ""
    log_info "Exported dataset to $outfile ($fmt)"
}

function _dataset_clear() {
    echo ""
    printf "  ${R}[!]${NC} This will delete all ${BOLD}$(dataset_count)${NC} entries.\n"
    printf "  ${Y}    Type 'yes' to confirm: ${NC}"
    read -r confirm
    if [[ "$confirm" == "yes" ]]; then
        : > "$OR_DATASET_FILE"
        : > "$OR_VISITED_FILE"
        : > "$OR_QUEUE_FILE"
        or_hit "Dataset cleared"
        log_info "Dataset cleared by user"
    else
        or_info "Cancelled"
    fi
    echo ""
}
