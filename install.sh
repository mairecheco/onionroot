#!/usr/bin/env bash
# OnionRoot — install.sh
# Supports both root and rootless installation.
#
# Root install   (sudo bash install.sh):
#   Files  → /opt/onionroot/
#   Binary → /usr/local/bin/onionroot
#
# Rootless install (bash install.sh):
#   Files  → ~/.local/share/onionroot/
#   Binary → ~/.local/bin/onionroot  (add to PATH if needed)

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ─────────────────────────────────────────────────────────────────
P='\033[0m\033[35m'; LP='\033[0m\033[1m\033[35m'
G='\033[0m\033[32m'; R='\033[0m\033[1m\033[31m'
Y='\033[0m\033[33m'; W='\033[0m\033[37m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

p_hit()  { printf "  ${G}[+]${NC} %s\n" "$*"; }
p_info() { printf "  ${P}[~]${NC} %s\n" "$*"; }
p_warn() { printf "  ${Y}[!]${NC} %s\n" "$*"; }
p_err()  { printf "  ${R}[✗]${NC} %s\n" "$*" >&2; }
p_step() { printf "\n  ${LP}${BOLD}━━ %s${NC}\n\n" "$*"; }
p_div()  { printf "  ${P}──────────────────────────────────────────────────────${NC}\n"; }

# ── Banner ─────────────────────────────────────────────────────────────────
printf "${P}"
cat <<'EOF'

   ▄██████▄  ███▄▄▄▄    ▄█   ▄██████▄  ███▄▄▄▄
  ███    ███ ███▀▀▀██▄ ███  ███    ███ ███▀▀▀██▄
  ███    ███ ███   ███ ███▌ ███    ███ ███   ███
  ███    ███ ███   ███ ███▌ ███    ███ ███   ███
  ███    ███ ███   ███ ███▌ ███    ███ ███   ███
  ███    ███ ███   ███ ███  ███    ███ ███   ███
  ███    ███ ███   ███ ███  ███    ███ ███   ███
   ▀██████▀   ▀█   █▀  █▀    ▀██████▀   ▀█   █▀

EOF
printf "${NC}"
p_div
printf "  ${LP}${BOLD}  OnionRoot Installer${NC}\n"
p_div
echo ""

# ── Detect install mode ─────────────────────────────────────────────────────
IS_TERMUX=0
[[ -n "${PREFIX:-}" && "$PREFIX" == *"/com.termux/"* ]] && IS_TERMUX=1

if [[ $EUID -eq 0 ]]; then
    INSTALL_MODE="root"
    INSTALL_DIR="/opt/onionroot"
    BIN_DIR="/usr/local/bin"
    BIN_LINK="${BIN_DIR}/onionroot"
    DATA_DIR="${SUDO_HOME:-$HOME}/.onionroot"
    REAL_USER="${SUDO_USER:-root}"
else
    INSTALL_MODE="rootless"
    if [[ $IS_TERMUX -eq 1 ]]; then
        INSTALL_DIR="${HOME}/onionroot"
        BIN_DIR="${PREFIX}/bin"
    else
        INSTALL_DIR="${HOME}/.local/share/onionroot"
        BIN_DIR="${HOME}/.local/bin"
    fi
    BIN_LINK="${BIN_DIR}/onionroot"
    DATA_DIR="${HOME}/.onionroot"
    REAL_USER="$(whoami)"
fi

printf "  ${DIM}Install mode:${NC}  "
if [[ "$INSTALL_MODE" == "root" ]]; then
    printf "${G}${BOLD}ROOT${NC}\n"
else
    printf "${Y}${BOLD}ROOTLESS${NC}\n"
fi
printf "  ${DIM}Install dir:${NC}   ${W}%s${NC}\n" "$INSTALL_DIR"
printf "  ${DIM}Binary:${NC}        ${W}%s${NC}\n" "$BIN_LINK"
printf "  ${DIM}Data dir:${NC}      ${W}%s${NC}\n" "$DATA_DIR"
echo ""

# ── Detect package manager ──────────────────────────────────────────────────
p_step "Detecting system"
PKG_MGR=""
if   command -v apt-get &>/dev/null; then PKG_MGR="apt-get"; p_hit "Debian/Ubuntu/Kali"
elif command -v pacman  &>/dev/null; then PKG_MGR="pacman";  p_hit "Arch Linux"
elif command -v dnf     &>/dev/null; then PKG_MGR="dnf";     p_hit "Fedora/RHEL"
elif [[ $IS_TERMUX -eq 1 ]];         then PKG_MGR="pkg";     p_hit "Termux"
else p_warn "Unknown distro — install dependencies manually"
fi

# ── Install dependencies ────────────────────────────────────────────────────
p_step "Installing dependencies"

install_pkg() {
    local pkg="$1"
    p_info "Installing $pkg..."
    case $PKG_MGR in
        apt-get) apt-get install -y "$pkg" -q 2>/dev/null && return 0 ;;
        pacman)  pacman -S --noconfirm "$pkg" 2>/dev/null && return 0 ;;
        dnf)     dnf install -y "$pkg" 2>/dev/null && return 0 ;;
        pkg)     pkg install -y "$pkg" 2>/dev/null && return 0 ;;
        *)       p_warn "Cannot auto-install $pkg"; return 1 ;;
    esac
    return 1
}

check_or_install() {
    local cmd="$1" pkg="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        p_hit "$cmd already installed"
    elif [[ -n "$PKG_MGR" ]]; then
        if [[ "$INSTALL_MODE" == "root" || $IS_TERMUX -eq 1 ]]; then
            install_pkg "$pkg" && p_hit "$cmd installed" || p_warn "Failed to install $cmd"
        else
            p_warn "$cmd not found — run: ${W}sudo apt install $pkg${NC}"
        fi
    fi
}

# Core — required
check_or_install tor
check_or_install curl
check_or_install python3

# Recommended — only attempt in root mode
if [[ "$INSTALL_MODE" == "root" || $IS_TERMUX -eq 1 ]]; then
    check_or_install git
    check_or_install nmap
    check_or_install torsocks
else
    echo ""
    printf "  ${Y}  Rootless mode — skipping system package installs.${NC}\n"
    printf "  ${DIM}  For full scan capabilities, install manually:${NC}\n"
    printf "  ${DIM}  sudo apt install tor curl nmap torsocks python3${NC}\n"
fi

# ── Copy files ──────────────────────────────────────────────────────────────
p_step "Installing OnionRoot"

if [[ -d "$INSTALL_DIR" && "$INSTALL_DIR" != "$REPO_DIR" ]]; then
    p_info "Removing previous install at $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

if [[ "$REPO_DIR" != "$INSTALL_DIR" ]]; then
    cp -r "$REPO_DIR" "$INSTALL_DIR"
    p_hit "Copied to $INSTALL_DIR"
else
    p_info "Already in install directory"
fi

chmod +x "$INSTALL_DIR/onionroot"
find "$INSTALL_DIR/modules" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$INSTALL_DIR/modules" -name "*.py" -exec chmod +x {} \; 2>/dev/null || true

# ── Create binary link ───────────────────────────────────────────────────────
p_step "Linking binary"
mkdir -p "$BIN_DIR"
# Force remove any stale symlink or old file (e.g. old onionroot.sh installs)
rm -f "$BIN_LINK" "${BIN_DIR}/onionroot.sh" 2>/dev/null || true
ln -sf "$INSTALL_DIR/onionroot" "$BIN_LINK"
p_hit "Linked: $BIN_LINK → $INSTALL_DIR/onionroot"

# For rootless, warn if ~/.local/bin is not in PATH
if [[ "$INSTALL_MODE" == "rootless" && $IS_TERMUX -eq 0 ]]; then
    if ! echo "$PATH" | grep -q "$BIN_DIR"; then
        p_warn "${BIN_DIR} is not in your PATH"
        printf "  ${DIM}  Add to ~/.bashrc or ~/.zshrc:${NC}\n"
        printf "  ${W}  export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}\n"
    fi
fi

# ── Setup data directory ─────────────────────────────────────────────────────
p_step "Setting up data directory"
mkdir -p "${DATA_DIR}/cache"
touch "${DATA_DIR}/dataset.jsonl" \
      "${DATA_DIR}/visited.txt" \
      "${DATA_DIR}/queue.txt" 2>/dev/null || true

# Fix ownership if running as sudo
if [[ $EUID -eq 0 && "$REAL_USER" != "root" ]]; then
    chown -R "${REAL_USER}:${REAL_USER}" "$DATA_DIR" 2>/dev/null || true
fi
p_hit "Data directory: $DATA_DIR"

# ── Tor setup hint ───────────────────────────────────────────────────────────
p_step "Tor setup"
if command -v tor &>/dev/null; then
    if [[ $IS_TERMUX -eq 1 ]]; then
        printf "  ${DIM}  Start Tor:   ${W}tor &${NC}\n"
    elif [[ "$INSTALL_MODE" == "root" ]]; then
        printf "  ${DIM}  Enable Tor:  ${W}sudo systemctl enable --now tor${NC}\n"
    else
        printf "  ${DIM}  Start Tor:   ${W}tor &${NC}  or  ${W}sudo systemctl start tor${NC}\n"
    fi
    printf "  ${DIM}  Proxy:       ${W}127.0.0.1:9050 (SOCKS5)${NC}\n"
else
    p_warn "Tor not found — install it to use any network feature"
fi

# ── Mode capabilities summary ────────────────────────────────────────────────
echo ""
p_div
if [[ "$INSTALL_MODE" == "root" ]]; then
    printf "  ${G}${BOLD}  ROOT MODE installed${NC}\n\n"
    printf "  ${G}  ✓${NC}  SYN port scan (nmap -sS via torsocks)\n"
    printf "  ${G}  ✓${NC}  OS and service fingerprinting\n"
    printf "  ${G}  ✓${NC}  System-wide install (/opt + /usr/local/bin)\n"
    printf "  ${G}  ✓${NC}  All modules available\n"
else
    printf "  ${Y}${BOLD}  ROOTLESS MODE installed${NC}\n\n"
    printf "  ${G}  ✓${NC}  TCP connect scan (torsocks nmap -sT)\n"
    printf "  ${G}  ✓${NC}  curl SOCKS5 probe fallback\n"
    printf "  ${G}  ✓${NC}  All non-scan modules fully functional\n"
    printf "  ${Y}  ~${NC}  No SYN scan, no OS detection (needs root)\n"
    printf "  ${DIM}      Upgrade: ${W}sudo onionroot scan --root <target>${NC}\n"
fi
p_div
echo ""
printf "  ${W}  Run:${NC}  ${P}onionroot help${NC}\n"
printf "  ${W}  Docs:${NC} ${DIM}github.com/mairecheco/onionroot${NC}\n\n"
