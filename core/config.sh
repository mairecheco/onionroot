#!/usr/bin/env bash
# OnionRoot — core/config.sh
# Global configuration, constants, and color definitions

#########################################################################
# Version
#########################################################################

readonly OR_VERSION="1.0.0"
readonly OR_AUTHOR="MAIRECHE"
readonly OR_GITHUB="github.com/mairecheco/onionroot"
readonly OR_INSTAGRAM="@maireche.exe"
readonly OR_TIKTOK="@abdou_mhf7"

#########################################################################
# Paths
#########################################################################

readonly OR_DATA_DIR="${HOME}/.onionroot"
readonly OR_CACHE_DIR="${OR_DATA_DIR}/cache"
readonly OR_LOG_FILE="${OR_DATA_DIR}/onionroot.log"
readonly OR_DATASET_FILE="${OR_DATA_DIR}/dataset.jsonl"
readonly OR_VISITED_FILE="${OR_DATA_DIR}/visited.txt"
readonly OR_QUEUE_FILE="${OR_DATA_DIR}/queue.txt"

#########################################################################
# Tor / Network
#########################################################################

OR_TOR_PROXY="${OR_TOR_PROXY:-127.0.0.1:9050}"
OR_TOR_HOST="${OR_TOR_PROXY%%:*}"
OR_TOR_PORT="${OR_TOR_PROXY##*:}"
OR_DEPTH="${OR_DEPTH:-2}"
OR_OUTPUT_FILE="${OR_OUTPUT_FILE:-}"
OR_DEBUG="${OR_DEBUG:-0}"

#########################################################################
# Root / Rootless Mode
#########################################################################
# Auto-detected if not set via --root / --rootless flag.
# root     — EUID=0, full nmap/torsocks capabilities, installs to /opt
# rootless — normal user, curl SOCKS5 probes only, installs to ~/.local
if [[ -z "${OR_MODE:-}" ]]; then
    if [[ $EUID -eq 0 ]]; then
        OR_MODE="root"
    else
        OR_MODE="rootless"
    fi
fi
export OR_MODE

# Per-mode capability flags (set after mode is known)
OR_CAN_NMAP=0
OR_CAN_TORSOCKS=0
OR_INSTALL_DIR_DEFAULT="/opt/onionroot"
OR_BIN_DIR_DEFAULT="/usr/local/bin"

if [[ "$OR_MODE" == "root" ]]; then
    command -v nmap     &>/dev/null && OR_CAN_NMAP=1     || true
    command -v torsocks &>/dev/null && OR_CAN_TORSOCKS=1 || true
else
    OR_INSTALL_DIR_DEFAULT="${HOME}/.local/share/onionroot"
    OR_BIN_DIR_DEFAULT="${HOME}/.local/bin"
    # Connect scan (-sT) and torsocks both work without root
    command -v nmap     &>/dev/null && OR_CAN_NMAP=1     || true
    command -v torsocks &>/dev/null && OR_CAN_TORSOCKS=1 || true
fi

readonly OR_USER_AGENT="Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0"
readonly OR_CONNECT_TIMEOUT=30
readonly OR_MAX_TIME=60
readonly OR_RETRY=2
readonly OR_RATE_LIMIT=2     # seconds between requests (be polite)

#########################################################################
# Onion address regex patterns
#########################################################################

# v2 (deprecated) 16-char, v3 56-char base32
readonly OR_ONION_REGEX='[a-z2-7]{16,56}\.onion'

#########################################################################
# Colors  (disable if not a TTY or --no-color passed)
#########################################################################

if [[ -t 1 && -n "${TERM:-}" && "${NO_COLOR:-}" != "1" ]]; then
    P="$(printf '\033[0m\033[35m')"
    LP="$(printf '\033[0m\033[1m\033[35m')"
    G="$(printf '\033[0m\033[32m')"
    R="$(printf '\033[0m\033[1m\033[31m')"
    Y="$(printf '\033[0m\033[33m')"
    C="$(printf '\033[0m\033[36m')"
    W="$(printf '\033[0m\033[37m')"
    B="$(printf '\033[0m\033[34m')"
    BOLD="$(printf '\033[1m')"
    DIM="$(printf '\033[2m')"
    NC="$(printf '\033[0m')"
else
    P="" LP="" G="" R="" Y="" C="" W="" B="" BOLD="" DIM="" NC=""
fi

_disable_colors() {
    P="" LP="" G="" R="" Y="" C="" W="" B="" BOLD="" DIM="" NC=""
}

#########################################################################
# Output helpers
#########################################################################

or_hit()     { printf "  ${G}[+]${NC} %s\n" "$*"; }
or_info()    { printf "  ${C}[~]${NC} %s\n" "$*"; }
or_warn()    { printf "  ${Y}[!]${NC} %s\n" "$*"; }
or_err()     { printf "  ${R}[✗]${NC} %s\n" "$*" >&2; }
or_section() {
    printf "\n  ${P}──────────────────────────────────────────────────────${NC}\n"
    printf "  ${LP}${BOLD}  %s${NC}\n" "$*"
    printf "  ${P}──────────────────────────────────────────────────────${NC}\n\n"
}
or_divider() {
    printf "  ${P}  ──────────────────────────────────────────────────${NC}\n"
}
or_kv() {
    printf "  ${DIM}  %-18s${NC} ${W}%s${NC}\n" "$1" "$2"
}
