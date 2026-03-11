#!/usr/bin/env bash
# ============================================================================
#  Cyberdine Strategies UI - Update Script
#
#  Clean update: pulls latest, removes everything, rebuilds from scratch.
#    1. Pull latest patches from GitHub
#    2. Remove ALL backend patches from FreqTrade Python files
#    3. Delete cs_ui entirely
#    4. Re-clone FreqUI fresh
#    5. Copy patches + assets, apply, build, symlink
#
#  Usage:  cd ~/Cyberdine_UI && ./update.sh
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

# ════════════════════════════════════════════════════════════════
# STEP 1: Pull latest from GitHub
# ════════════════════════════════════════════════════════════════
info "Step 1: Pulling latest changes from GitHub..."
cd "$REPO_DIR"
git pull || { error "Git pull failed."; exit 1; }
success "Repo updated"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 2: Load paths from config (saved by setup.sh)
# ════════════════════════════════════════════════════════════════
info "Step 2: Loading configuration..."

CONFIG_FILE="$REPO_DIR/.cyberdine_config"
if [ ! -f "$CONFIG_FILE" ]; then
    error "Config file not found: $CONFIG_FILE"
    error "Run setup.sh first, or create it with:"
    echo "  echo 'USER_DATA_DIR=/home/freq/freqtrade/user_data' > $CONFIG_FILE"
    echo "  echo 'FT_PACKAGE_DIR=/home/freq/freqtrade/freqtrade' >> $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

CS_UI_DIR="$USER_DATA_DIR/cs_ui"
PATCHES_DIR="$CS_UI_DIR/patches"

export FT_PACKAGE_DIR
export CS_UI_DIR

info "  user_data: $USER_DATA_DIR"
info "  cs_ui:     $CS_UI_DIR"
info "  freqtrade: $FT_PACKAGE_DIR"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 3: Clean backend — remove ALL injected code from Python
# ════════════════════════════════════════════════════════════════
info "Step 3: Removing backend patches from FreqTrade..."

RPC_FILE="$FT_PACKAGE_DIR/rpc/rpc.py"
API_FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"

python3 - "$RPC_FILE" "$API_FILE" << 'CLEANPY'
import sys, re

rpc_file = sys.argv[1]
api_file = sys.argv[2]

# ── Clean rpc.py: remove all injected methods ──
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
    print("    rpc.py: nothing to remove")

# ── Clean api_trading.py: remove ALL lines containing our route identifiers ──
# Simple and nuclear: any line containing these strings gets removed
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
    print("    api_trading.py: nothing to remove")
CLEANPY

success "Backend cleaned"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 4: Delete cs_ui entirely and re-clone fresh
# ════════════════════════════════════════════════════════════════
info "Step 4: Deleting cs_ui and cloning fresh FreqUI..."
rm -rf "$CS_UI_DIR"
git clone https://github.com/freqtrade/frequi.git "$CS_UI_DIR"
success "Fresh FreqUI cloned"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 5: Copy patches + assets from repo
# ════════════════════════════════════════════════════════════════
info "Step 5: Copying patches and assets..."
mkdir -p "$PATCHES_DIR"
cp "$REPO_DIR"/patches/*.sh "$PATCHES_DIR/" 2>/dev/null || true
cp "$REPO_DIR"/patches/README.md "$PATCHES_DIR/" 2>/dev/null || true
chmod +x "$PATCHES_DIR"/*.sh 2>/dev/null || true
[ -d "$REPO_DIR/assets" ] && cp "$REPO_DIR"/assets/* "$PATCHES_DIR/" 2>/dev/null || true
success "Patches and assets copied"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 6: Apply all patches fresh
# ════════════════════════════════════════════════════════════════
info "Step 6: Applying all patches..."
PATCH_COUNT=0
for patch_file in "$PATCHES_DIR"/*.sh; do
    [ -f "$patch_file" ] || continue
    info "  Applying: $(basename "$patch_file")"
    bash "$patch_file"
    PATCH_COUNT=$((PATCH_COUNT + 1))
done
[ "$PATCH_COUNT" -eq 0 ] && warn "No patches found." || success "Applied $PATCH_COUNT patch(es)"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 7: Install deps + build
# ════════════════════════════════════════════════════════════════
info "Step 7: Building UI..."
cd "$CS_UI_DIR"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
set +u; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true; set -u

pnpm install
pnpm build

if [ ! -f "$CS_UI_DIR/dist/index.html" ]; then
    error "Build failed."
    exit 1
fi
[ -f "$CS_UI_DIR/public/cyberdine-icon.png" ] && cp "$CS_UI_DIR/public/cyberdine-icon.png" "$CS_UI_DIR/dist/" 2>/dev/null || true
success "Build complete"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 8: Symlink
# ════════════════════════════════════════════════════════════════
UI_INSTALLED_DIR="$FT_PACKAGE_DIR/rpc/api_server/ui/installed"
if [ -L "$UI_INSTALLED_DIR" ]; then
    rm "$UI_INSTALLED_DIR"
fi
if [ -d "$UI_INSTALLED_DIR" ]; then
    mv "$UI_INSTALLED_DIR" "${UI_INSTALLED_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
fi
mkdir -p "$(dirname "$UI_INSTALLED_DIR")"
ln -s "$CS_UI_DIR/dist" "$UI_INSTALLED_DIR"
success "Symlink set"

# ════════════════════════════════════════════════════════════════
# STEP 9: Create helper scripts
# ════════════════════════════════════════════════════════════════
cat > "$CS_UI_DIR/rebuild.sh" << 'REBUILD_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
set +u; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true; set -u
echo "[INFO] Rebuilding FreqUI from: $SCRIPT_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build
[ -f "$SCRIPT_DIR/public/cyberdine-icon.png" ] && cp "$SCRIPT_DIR/public/cyberdine-icon.png" "$SCRIPT_DIR/dist/" 2>/dev/null || true
[ -f "$SCRIPT_DIR/dist/index.html" ] && echo "[OK] Build successful." || echo "[ERROR] Build failed"
REBUILD_EOF
chmod +x "$CS_UI_DIR/rebuild.sh"

cat > "$CS_UI_DIR/relink.sh" << RELINK_EOF
#!/usr/bin/env bash
set -euo pipefail
UI_TARGET="$UI_INSTALLED_DIR"
CS_UI_DIST="$CS_UI_DIR/dist"
[ -L "\$UI_TARGET" ] && rm "\$UI_TARGET"
[ -d "\$UI_TARGET" ] && mv "\$UI_TARGET" "\${UI_TARGET}.bak.\$(date +%Y%m%d_%H%M%S)"
mkdir -p "\$(dirname "\$UI_TARGET")"
ln -s "\$CS_UI_DIST" "\$UI_TARGET"
echo "[OK] Symlink set: \$UI_TARGET -> \$CS_UI_DIST"
RELINK_EOF
chmod +x "$CS_UI_DIR/relink.sh"

cat > "$CS_UI_DIR/apply_patches.sh" << APPLYPATCH_EOF
#!/usr/bin/env bash
set -euo pipefail
export FT_PACKAGE_DIR="$FT_PACKAGE_DIR"
export CS_UI_DIR="$CS_UI_DIR"
PATCHES_DIR="$PATCHES_DIR"
echo "[INFO] Applying patches from \$PATCHES_DIR ..."
COUNT=0
for patch_file in "\$PATCHES_DIR"/*.sh; do
    [ -f "\$patch_file" ] || continue
    echo "[INFO] Applying: \$(basename "\$patch_file")"
    bash "\$patch_file"
    COUNT=\$((COUNT + 1))
done
[ "\$COUNT" -eq 0 ] && echo "[INFO] No patches found." || echo "[OK] Applied \$COUNT patch(es). Restart freqtrade."
APPLYPATCH_EOF
chmod +x "$CS_UI_DIR/apply_patches.sh"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Update Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "  ${YELLOW}Restart FreqTrade for backend patches to take effect.${NC}"
echo ""
