#!/usr/bin/env bash
# ============================================================================
#  Cyberdine Strategies UI - Update Script
#
#  Pulls latest patches from the repo and re-applies them.
#  Run this from the cloned Cyberdine_UI repo directory.
#
#  Usage:
#    cd ~/Cyberdine_UI
#    ./update.sh
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  Cyberdine Strategies UI - Update${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# ── Pull latest from GitHub ──
info "Pulling latest changes from GitHub..."
cd "$REPO_DIR"
git pull || { error "Git pull failed. Resolve conflicts and try again."; exit 1; }
success "Repo updated"

# ── Find cs_ui directory ──
# Try common locations
CS_UI_DIR=""
for candidate in \
    "$HOME/freqtrade/user_data/cs_ui" \
    "/home/freq/freqtrade/user_data/cs_ui" \
    "$(dirname "$REPO_DIR")/freqtrade/user_data/cs_ui"; do
    if [ -d "$candidate/src" ]; then
        CS_UI_DIR="$candidate"
        break
    fi
done

if [ -z "$CS_UI_DIR" ]; then
    warn "Could not auto-detect cs_ui directory."
    read -rp "Enter the full path to your cs_ui directory: " CS_UI_DIR
    if [ ! -d "$CS_UI_DIR" ]; then
        error "'$CS_UI_DIR' does not exist. Run setup.sh first."
        exit 1
    fi
fi

PATCHES_DIR="$CS_UI_DIR/patches"
info "cs_ui directory: $CS_UI_DIR"
echo ""

# ── Copy patches ──
info "Copying patches..."
mkdir -p "$PATCHES_DIR"
cp "$REPO_DIR"/patches/*.sh "$PATCHES_DIR/" 2>/dev/null || true
cp "$REPO_DIR"/patches/README.md "$PATCHES_DIR/" 2>/dev/null || true
chmod +x "$PATCHES_DIR"/*.sh 2>/dev/null || true
success "Patches copied"

# ── Copy assets ──
info "Copying assets..."
if [ -d "$REPO_DIR/assets" ]; then
    cp "$REPO_DIR"/assets/* "$PATCHES_DIR/" 2>/dev/null || true
    success "Assets copied"
fi

# ── Apply patches ──
echo ""
if [ -f "$CS_UI_DIR/apply_patches.sh" ]; then
    info "Applying patches..."
    cd "$CS_UI_DIR"
    ./apply_patches.sh
else
    error "apply_patches.sh not found in $CS_UI_DIR — run setup.sh first."
    exit 1
fi

# ── Rebuild ──
echo ""
if [ -f "$CS_UI_DIR/rebuild.sh" ]; then
    info "Rebuilding UI..."
    ./rebuild.sh
else
    error "rebuild.sh not found in $CS_UI_DIR — run setup.sh first."
    exit 1
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Update Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "  ${YELLOW}Restart FreqTrade for backend patches to take effect.${NC}"
echo ""
