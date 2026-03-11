#!/usr/bin/env bash
# ============================================================================
#  setup_custom_freqUI.sh
#  Cyberdine Strategies UI - Custom FreqUI Fork Setup
#
#  Clones/updates your custom FreqUI fork, builds it, symlinks it into
#  freqtrade, and auto-applies all backend patches from cs_ui/patches/.
#
#  Usage:
#    chmod +x setup_custom_freqUI.sh
#    ./setup_custom_freqUI.sh
#
#  Patches:
#    Drop any .sh files into cs_ui/patches/ and they will be auto-applied.
#    Each patch receives two env vars:
#      $FT_PACKAGE_DIR  - path to the freqtrade Python package
#      $CS_UI_DIR       - path to the cs_ui directory
#    Patches should be idempotent (safe to run multiple times).
# ============================================================================

set -euo pipefail

# ---------- colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  Cyberdine Strategies UI Setup${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# ============================================================
# STEP 1: Get user_data path
# ============================================================
read -rp "Enter the full path to your user_data directory (e.g. /home/you/freqtrade/user_data): " USER_DATA_DIR
USER_DATA_DIR="${USER_DATA_DIR/#\~/$HOME}"

if [ ! -d "$USER_DATA_DIR" ]; then
    error "Directory '$USER_DATA_DIR' does not exist."
    read -rp "Create it? (y/n): " CREATE_DIR
    if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
        mkdir -p "$USER_DATA_DIR"
        success "Created $USER_DATA_DIR"
    else
        error "Aborting."
        exit 1
    fi
fi

USER_DATA_DIR="$(cd "$USER_DATA_DIR" && pwd)"
CS_UI_DIR="$USER_DATA_DIR/cs_ui"
PATCHES_DIR="$CS_UI_DIR/patches"

info "user_data directory: $USER_DATA_DIR"
info "Custom UI will be at: $CS_UI_DIR"
echo ""

# ============================================================
# STEP 2: Check / install Node.js
# ============================================================
install_node_nvm() {
    info "Installing nvm (Node Version Manager)..."
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ ! -d "$NVM_DIR" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi
    set +u
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    info "Installing Node.js LTS via nvm..."
    nvm install --lts
    nvm use --lts
    set -u
    success "Node.js $(node --version) installed via nvm"
}

check_node() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    set +u
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
    set -u
    if command -v node &>/dev/null; then
        NODE_MAJOR=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$NODE_MAJOR" -ge 18 ]; then
            success "Node.js $(node --version) found"
            return 0
        fi
    fi
    return 1
}

if ! check_node; then
    info "Node.js >= 18 is required to build FreqUI."
    read -rp "Install Node.js via nvm? (y/n): " INSTALL_NODE
    if [[ "$INSTALL_NODE" =~ ^[Yy]$ ]]; then
        install_node_nvm
    else
        error "Node.js is required. Install it manually and re-run."
        exit 1
    fi
fi

# ============================================================
# STEP 3: Check / install pnpm
# ============================================================
if ! command -v pnpm &>/dev/null; then
    info "Installing pnpm..."
    if command -v corepack &>/dev/null; then
        corepack enable
        corepack prepare pnpm@latest --activate 2>/dev/null || npm install -g pnpm
    else
        npm install -g pnpm
    fi
    command -v pnpm &>/dev/null || { error "Failed to install pnpm."; exit 1; }
fi
success "pnpm $(pnpm --version) found"
echo ""

# ============================================================
# STEP 4: Clone or update FreqUI
# ============================================================
FREQUI_REPO="https://github.com/freqtrade/frequi.git"

if [ -d "$CS_UI_DIR/.git" ]; then
    warn "cs_ui directory already exists with a git repo."
    read -rp "Pull latest and rebuild? (y/n): " PULL_LATEST
    if [[ "$PULL_LATEST" =~ ^[Yy]$ ]]; then
        info "Pulling latest changes..."
        cd "$CS_UI_DIR"
        git pull --ff-only || {
            warn "Fast-forward pull failed (you may have local commits). Building with current source."
        }
    fi
else
    if [ -d "$CS_UI_DIR" ]; then
        warn "$CS_UI_DIR exists but is not a git repo."
        read -rp "Remove it and clone fresh? (y/n): " REMOVE_DIR
        if [[ "$REMOVE_DIR" =~ ^[Yy]$ ]]; then
            rm -rf "$CS_UI_DIR"
        else
            error "Cannot continue. Aborting."
            exit 1
        fi
    fi
    info "Cloning FreqUI into $CS_UI_DIR ..."
    git clone "$FREQUI_REPO" "$CS_UI_DIR"
    success "Cloned FreqUI"
fi

# ============================================================
# STEP 5: Create patches directory & default patches
# ============================================================
mkdir -p "$PATCHES_DIR"

# --- Default patch: Live Candle ---
if [ ! -f "$PATCHES_DIR/01_live_candle.sh" ]; then
    info "Creating default patch: 01_live_candle.sh"
    cat > "$PATCHES_DIR/01_live_candle.sh" << 'PATCH_LIVE_CANDLE'
#!/usr/bin/env bash
# ============================================================
# Patch: Live Candle on Chart
# Adds /pair_candles/live endpoint to freqtrade backend.
# Reads current incomplete candle from in-memory cache.
# Zero exchange API calls.
# ============================================================
set -euo pipefail

RPC_FILE="$FT_PACKAGE_DIR/rpc/rpc.py"
API_FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"

echo "  Patching rpc.py..."
if grep -q "_rpc_live_candle" "$RPC_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i '/def _ws_all_analysed_dataframes/i\
    def _rpc_live_candle(self, pair: str, timeframe: str) -> dict[str, Any]:\
        """Return the current incomplete candle from the exchange cache.\
        Zero exchange API calls - reads from in-memory klines cache only.\
        """\
        from freqtrade.exchange import timeframe_to_msecs\
\
        df = self._freqtrade.dataprovider.ohlcv(pair, timeframe)\
        if df.empty:\
            return {"pair": pair, "timeframe": timeframe, "candle": None}\
\
        last_row = df.iloc[-1]\
        return {\
            "pair": pair,\
            "timeframe": timeframe,\
            "timeframe_ms": timeframe_to_msecs(timeframe),\
            "candle": {\
                "date": int(last_row["date"].timestamp() * 1000),\
                "open": float(last_row["open"]),\
                "high": float(last_row["high"]),\
                "low": float(last_row["low"]),\
                "close": float(last_row["close"]),\
                "volume": float(last_row["volume"]),\
            },\
        }\
' "$RPC_FILE"
    echo "    Done."
fi

echo "  Patching api_trading.py..."
if grep -q "pair_candles_live" "$API_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i '/@router.get("\/pair_candles", response_model=PairHistory/i\
@router.get("/pair_candles/live", tags=["Candle data"])\
def pair_candles_live(pair: str, timeframe: str, rpc: RPC = Depends(get_rpc)):\
    return rpc._rpc_live_candle(pair, timeframe)\
\
' "$API_FILE"
    echo "    Done."
fi
PATCH_LIVE_CANDLE
    chmod +x "$PATCHES_DIR/01_live_candle.sh"
fi

# --- Patches README ---
if [ ! -f "$PATCHES_DIR/README.md" ]; then
    cat > "$PATCHES_DIR/README.md" << 'PATCH_README'
# Backend Patches

Drop `.sh` files here to auto-apply backend patches during setup.

## Rules:
- Files run in alphabetical order (use `01_`, `02_` prefixes)
- Each patch gets `$FT_PACKAGE_DIR` and `$CS_UI_DIR` env vars
- Patches MUST be idempotent (safe to run multiple times)
- Always `grep -q` to check if already applied before modifying

## Example:
```bash
#!/usr/bin/env bash
set -euo pipefail
FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"
if grep -q "my_endpoint" "$FILE"; then
    echo "Already patched."
else
    sed -i '/some_line/a\
@router.get("/my_endpoint")\
def my_endpoint():\
    return {"ok": True}\
' "$FILE"
fi
```
PATCH_README
fi

# ============================================================
# STEP 6: Install deps & build
# ============================================================
cd "$CS_UI_DIR"

info "Installing dependencies (pnpm install)..."
pnpm install
success "Dependencies installed"

info "Building FreqUI (pnpm build)..."
pnpm build

if [ ! -f "$CS_UI_DIR/dist/index.html" ]; then
    error "Build failed - dist/index.html not found."
    exit 1
fi
success "Build complete"
echo ""

# ============================================================
# STEP 7: Find freqtrade package path
# ============================================================
info "Locating freqtrade installation..."

FT_PACKAGE_DIR=""

# Method 1: Direct python import
if command -v python3 &>/dev/null; then
    FT_PACKAGE_DIR=$(python3 -c "
import freqtrade; from pathlib import Path; print(Path(freqtrade.__file__).parent)
" 2>/dev/null || true)
fi

# Method 2: Check common venv locations
if [ -z "$FT_PACKAGE_DIR" ] || [ ! -d "$FT_PACKAGE_DIR" ]; then
    FT_PROJECT_DIR="$(dirname "$USER_DATA_DIR")"
    for venv_dir in "$FT_PROJECT_DIR/.venv" "$FT_PROJECT_DIR/.env" "$FT_PROJECT_DIR/venv"; do
        if [ -x "$venv_dir/bin/python" ]; then
            FT_PACKAGE_DIR=$("$venv_dir/bin/python" -c "
import freqtrade; from pathlib import Path; print(Path(freqtrade.__file__).parent)
" 2>/dev/null || true)
            [ -n "$FT_PACKAGE_DIR" ] && [ -d "$FT_PACKAGE_DIR" ] && break
        fi
    done
fi

# Method 3: Source install (editable / git clone)
if [ -z "$FT_PACKAGE_DIR" ] || [ ! -d "$FT_PACKAGE_DIR" ]; then
    FT_PROJECT_DIR="$(dirname "$USER_DATA_DIR")"
    if [ -f "$FT_PROJECT_DIR/freqtrade/__init__.py" ]; then
        FT_PACKAGE_DIR="$FT_PROJECT_DIR/freqtrade"
    fi
fi

if [ -z "$FT_PACKAGE_DIR" ] || [ ! -d "$FT_PACKAGE_DIR" ]; then
    warn "Could not auto-detect freqtrade installation."
    echo "  To find it: python -c \"import freqtrade; print(freqtrade.__file__)\""
    read -rp "Enter the freqtrade package directory: " FT_PACKAGE_DIR
    if [ ! -d "$FT_PACKAGE_DIR" ]; then
        error "'$FT_PACKAGE_DIR' does not exist. Aborting."
        exit 1
    fi
fi

export FT_PACKAGE_DIR
export CS_UI_DIR

UI_INSTALLED_DIR="$FT_PACKAGE_DIR/rpc/api_server/ui/installed"

info "freqtrade package: $FT_PACKAGE_DIR"
info "UI install target: $UI_INSTALLED_DIR"
echo ""

# ============================================================
# STEP 8: Symlink
# ============================================================
if [ -L "$UI_INSTALLED_DIR" ]; then
    CURRENT_TARGET=$(readlink -f "$UI_INSTALLED_DIR")
    if [ "$CURRENT_TARGET" = "$(cd "$CS_UI_DIR/dist" && pwd)" ]; then
        success "Symlink already correct."
    else
        warn "Updating symlink..."
        rm "$UI_INSTALLED_DIR"
        ln -s "$CS_UI_DIR/dist" "$UI_INSTALLED_DIR"
        success "Symlink updated"
    fi
elif [ -d "$UI_INSTALLED_DIR" ]; then
    BACKUP_DIR="${UI_INSTALLED_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
    info "Backing up existing UI to: $BACKUP_DIR"
    mv "$UI_INSTALLED_DIR" "$BACKUP_DIR"
    ln -s "$CS_UI_DIR/dist" "$UI_INSTALLED_DIR"
    success "Symlink created"
else
    mkdir -p "$(dirname "$UI_INSTALLED_DIR")"
    ln -s "$CS_UI_DIR/dist" "$UI_INSTALLED_DIR"
    success "Symlink created"
fi

# ============================================================
# STEP 9: Auto-apply all backend patches
# ============================================================
echo ""
info "Applying backend patches from $PATCHES_DIR ..."

PATCH_COUNT=0
if [ -d "$PATCHES_DIR" ]; then
    for patch_file in "$PATCHES_DIR"/*.sh; do
        [ -f "$patch_file" ] || continue
        PATCH_NAME=$(basename "$patch_file")
        info "Applying patch: $PATCH_NAME"
        bash "$patch_file"
        PATCH_COUNT=$((PATCH_COUNT + 1))
    done
fi

if [ "$PATCH_COUNT" -eq 0 ]; then
    info "No patches found."
else
    success "Applied $PATCH_COUNT patch(es)"
fi

# ============================================================
# STEP 10: Create helper scripts
# ============================================================

# --- rebuild.sh ---
cat > "$CS_UI_DIR/rebuild.sh" << 'REBUILD_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
set +u
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
set -u
echo "[INFO] Rebuilding FreqUI from: $SCRIPT_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build
if [ -f "$SCRIPT_DIR/dist/index.html" ]; then
    echo "[OK] Build successful. Refresh your browser (Ctrl+Shift+R)."
else
    echo "[ERROR] Build failed - dist/index.html not found"
    exit 1
fi
REBUILD_EOF
chmod +x "$CS_UI_DIR/rebuild.sh"

# --- relink.sh ---
cat > "$CS_UI_DIR/relink.sh" << RELINK_EOF
#!/usr/bin/env bash
set -euo pipefail
UI_TARGET="$UI_INSTALLED_DIR"
CS_UI_DIST="$CS_UI_DIR/dist"
if [ -L "\$UI_TARGET" ]; then
    echo "[OK] Symlink already exists: \$UI_TARGET -> \$(readlink -f "\$UI_TARGET")"
    exit 0
fi
if [ -d "\$UI_TARGET" ]; then
    BACKUP="\${UI_TARGET}.bak.\$(date +%Y%m%d_%H%M%S)"
    echo "[INFO] Backing up existing UI to \$BACKUP"
    mv "\$UI_TARGET" "\$BACKUP"
fi
mkdir -p "\$(dirname "\$UI_TARGET")"
ln -s "\$CS_UI_DIST" "\$UI_TARGET"
echo "[OK] Symlink restored: \$UI_TARGET -> \$CS_UI_DIST"
RELINK_EOF
chmod +x "$CS_UI_DIR/relink.sh"

# --- apply_patches.sh (standalone patch runner) ---
cat > "$CS_UI_DIR/apply_patches.sh" << APPLYPATCH_EOF
#!/usr/bin/env bash
# Re-apply all backend patches without rebuilding the UI.
# Run this after a freqtrade update to restore backend modifications.
set -euo pipefail
export FT_PACKAGE_DIR="$FT_PACKAGE_DIR"
export CS_UI_DIR="$CS_UI_DIR"
PATCHES_DIR="$PATCHES_DIR"

echo "[INFO] Applying backend patches from \$PATCHES_DIR ..."
COUNT=0
for patch_file in "\$PATCHES_DIR"/*.sh; do
    [ -f "\$patch_file" ] || continue
    echo "[INFO] Applying: \$(basename "\$patch_file")"
    bash "\$patch_file"
    COUNT=\$((COUNT + 1))
done
if [ "\$COUNT" -eq 0 ]; then
    echo "[INFO] No patches found."
else
    echo "[OK] Applied \$COUNT patch(es). Restart freqtrade to activate."
fi
APPLYPATCH_EOF
chmod +x "$CS_UI_DIR/apply_patches.sh"

# ============================================================
# Done
# ============================================================
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Cyberdine Strategies UI - Setup Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "  Source:     $CS_UI_DIR"
echo "  Built UI:   $CS_UI_DIR/dist/"
echo "  Symlink:    $UI_INSTALLED_DIR -> cs_ui/dist"
echo "  Patches:    $PATCHES_DIR/"
echo ""
echo -e "  ${YELLOW}Helper scripts in cs_ui/:${NC}"
echo "    rebuild.sh        - Rebuild UI after editing Vue source"
echo "    relink.sh         - Restore symlink after freqtrade update"
echo "    apply_patches.sh  - Re-apply backend patches after freqtrade update"
echo ""
echo -e "  ${YELLOW}After a freqtrade update, run:${NC}"
echo "    $CS_UI_DIR/relink.sh"
echo "    $CS_UI_DIR/apply_patches.sh"
echo "    (then restart freqtrade)"
echo ""
echo -e "  ${YELLOW}To add a new backend patch:${NC}"
echo "    1. Create $PATCHES_DIR/02_my_feature.sh"
echo "    2. Make it idempotent (check before patching)"
echo "    3. Commit it to your fork"
echo "    4. Run: $CS_UI_DIR/apply_patches.sh"
echo "    5. Restart freqtrade"
echo ""
echo -e "  ${YELLOW}DO NOT run 'freqtrade install-ui' — use relink.sh instead.${NC}"
echo ""