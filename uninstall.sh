#!/usr/bin/env bash
# ============================================================================
#  Cyberdine Strategies UI - Uninstall
#
#  Removes all Cyberdine customizations and restores default FreqUI.
#    1. Removes backend patches from FreqTrade Python files
#    2. Removes the cs_ui directory
#    3. Removes the symlink
#    4. Installs default FreqUI via freqtrade install-ui
#
#  Usage:  cd ~/Cyberdine_UI && ./uninstall.sh
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
echo -e "${RED}==========================================${NC}"
echo -e "${RED}  Cyberdine Strategies UI - Uninstall${NC}"
echo -e "${RED}==========================================${NC}"
echo ""
echo "This will:"
echo "  1. Remove all backend patches from FreqTrade"
echo "  2. Delete the cs_ui directory"
echo "  3. Remove the custom UI symlink"
echo "  4. Restore default FreqUI"
echo ""
read -rp "Are you sure you want to uninstall? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi
echo ""

# ════════════════════════════════════════════════════════════════
# Load paths from config
# ════════════════════════════════════════════════════════════════
CONFIG_FILE="$REPO_DIR/.cyberdine_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    warn "Config file not found. Trying to detect paths..."
    USER_DATA_DIR=""
    for candidate in "$HOME/freqtrade/user_data" "/home/freq/freqtrade/user_data"; do
        [ -d "$candidate" ] && USER_DATA_DIR="$candidate" && break
    done
    if [ -z "$USER_DATA_DIR" ]; then
        read -rp "Enter the full path to your user_data directory: " USER_DATA_DIR
    fi

    FT_PACKAGE_DIR=""
    if command -v python3 &>/dev/null; then
        FT_PACKAGE_DIR=$(python3 -c "import freqtrade; from pathlib import Path; print(Path(freqtrade.__file__).parent)" 2>/dev/null || true)
    fi
    if [ -z "$FT_PACKAGE_DIR" ] || [ ! -d "$FT_PACKAGE_DIR" ]; then
        FT_PROJECT_DIR="$(dirname "$USER_DATA_DIR")"
        [ -f "$FT_PROJECT_DIR/freqtrade/__init__.py" ] && FT_PACKAGE_DIR="$FT_PROJECT_DIR/freqtrade"
    fi
    if [ -z "$FT_PACKAGE_DIR" ] || [ ! -d "$FT_PACKAGE_DIR" ]; then
        read -rp "Enter the freqtrade package directory: " FT_PACKAGE_DIR
    fi
fi

CS_UI_DIR="$USER_DATA_DIR/cs_ui"
UI_INSTALLED_DIR="$FT_PACKAGE_DIR/rpc/api_server/ui/installed"

info "user_data: $USER_DATA_DIR"
info "cs_ui:     $CS_UI_DIR"
info "freqtrade: $FT_PACKAGE_DIR"
echo ""

# ════════════════════════════════════════════════════════════════
# Step 1: Remove backend patches
# ════════════════════════════════════════════════════════════════
info "Step 1: Removing backend patches from FreqTrade..."

RPC_FILE="$FT_PACKAGE_DIR/rpc/rpc.py"
API_FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"

python3 - "$RPC_FILE" "$API_FILE" << 'CLEANPY'
import sys, re

rpc_file = sys.argv[1]
api_file = sys.argv[2]

# Clean rpc.py: remove injected methods
with open(rpc_file, "r") as f:
    lines = f.readlines()

methods_to_remove = ["_rpc_live_candle", "_rpc_model_performance"]
new_lines = []
skipping = False
method_indent = 0
removed = []

i = 0
while i < len(lines):
    line = lines[i]
    is_ours = False
    for m in methods_to_remove:
        if f"def {m}" in line:
            is_ours = True
            removed.append(m)
            break

    if is_ours:
        skipping = True
        method_indent = len(line) - len(line.lstrip())
        i += 1
        continue

    if skipping:
        stripped = line.strip()
        if stripped == "":
            i += 1
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= method_indent and (stripped.startswith("def ") or stripped.startswith("@")):
            skipping = False
            new_lines.append(line)
            i += 1
            continue
        i += 1
        continue

    new_lines.append(line)
    i += 1

content = "".join(new_lines)
content = re.sub(r'\n{3,}', '\n\n', content)
with open(rpc_file, "w") as f:
    f.write(content)
for m in removed:
    print(f"    Removed {m} from rpc.py")
if not removed:
    print("    rpc.py: clean")

# Clean api_trading.py: remove all lines with our identifiers
with open(api_file, "r") as f:
    lines = f.readlines()

route_identifiers = ["pair_candles_live", "performance_model", "_rpc_live_candle", "_rpc_model_performance", "pair_candles/live", 'performance/model"']
new_lines = []
removed_count = 0
for line in lines:
    if any(rid in line for rid in route_identifiers):
        removed_count += 1
        continue
    new_lines.append(line)

content = "".join(new_lines)
content = re.sub(r'\n{3,}', '\n\n', content)
with open(api_file, "w") as f:
    f.write(content)

if removed_count > 0:
    print(f"    Removed {removed_count} lines from api_trading.py")
else:
    print("    api_trading.py: clean")
CLEANPY

success "Backend patches removed"
echo ""

# ════════════════════════════════════════════════════════════════
# Step 2: Remove symlink
# ════════════════════════════════════════════════════════════════
info "Step 2: Removing custom UI symlink..."
if [ -L "$UI_INSTALLED_DIR" ]; then
    rm "$UI_INSTALLED_DIR"
    success "Symlink removed"
elif [ -d "$UI_INSTALLED_DIR" ]; then
    warn "Not a symlink — leaving existing UI directory in place"
else
    success "No symlink found (already clean)"
fi
echo ""

# ════════════════════════════════════════════════════════════════
# Step 3: Delete cs_ui
# ════════════════════════════════════════════════════════════════
info "Step 3: Removing cs_ui directory..."
if [ -d "$CS_UI_DIR" ]; then
    rm -rf "$CS_UI_DIR"
    success "Deleted $CS_UI_DIR"
else
    success "cs_ui directory not found (already clean)"
fi
echo ""

# ════════════════════════════════════════════════════════════════
# Step 4: Restore default FreqUI
# ════════════════════════════════════════════════════════════════
info "Step 4: Restoring default FreqUI..."

# Check for backup
BACKUP_DIR=$(ls -td "${UI_INSTALLED_DIR}.bak."* 2>/dev/null | head -1)
if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$UI_INSTALLED_DIR"
    success "Restored from backup: $BACKUP_DIR"
else
    # Use freqtrade install-ui
    FT_PROJECT_DIR="$(dirname "$USER_DATA_DIR")"
    if [ -f "$FT_PROJECT_DIR/.venv/bin/freqtrade" ]; then
        "$FT_PROJECT_DIR/.venv/bin/freqtrade" install-ui
        success "Default FreqUI installed via freqtrade install-ui"
    elif command -v freqtrade &>/dev/null; then
        freqtrade install-ui
        success "Default FreqUI installed via freqtrade install-ui"
    else
        warn "Could not find freqtrade command."
        echo "  Run manually: freqtrade install-ui"
    fi
fi
echo ""

# ════════════════════════════════════════════════════════════════
# Step 5: Clean up config
# ════════════════════════════════════════════════════════════════
if [ -f "$CONFIG_FILE" ]; then
    rm "$CONFIG_FILE"
    success "Removed config file"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Uninstall Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "  FreqTrade has been restored to default FreqUI."
echo ""
echo -e "  ${YELLOW}Restart FreqTrade to complete the restoration.${NC}"
echo ""
echo "  To reinstall Cyberdine UI later:"
echo "    cd ~/Cyberdine_UI && ./setup.sh"
echo ""
