#!/usr/bin/env bash
# ============================================================================
#  Cyberdine Strategies UI - Setup Script
#
#  Run this from the cloned Cyberdine_UI repo directory.
#  It will clone FreqUI, copy patches + assets, build, symlink, and apply.
#
#  Usage:
#    cd ~/Cyberdine_UI
#    chmod +x setup.sh
#    ./setup.sh
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

# ---------- Detect repo directory ----------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATCHES="$REPO_DIR/patches"
REPO_ASSETS="$REPO_DIR/assets"

echo ""
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}  Cyberdine Strategies UI Setup${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""
info "Repo directory: $REPO_DIR"

# Verify repo has patches
if [ ! -d "$REPO_PATCHES" ] || [ -z "$(ls "$REPO_PATCHES"/*.sh 2>/dev/null)" ]; then
    error "No patches found in $REPO_PATCHES — is this the right directory?"
    exit 1
fi

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
    npm install -g pnpm 2>/dev/null || sudo npm install -g pnpm
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
# STEP 5: Copy patches + assets from repo
# ============================================================
mkdir -p "$PATCHES_DIR"

info "Copying patches from repo..."
cp "$REPO_PATCHES"/*.sh "$PATCHES_DIR/" 2>/dev/null || true
cp "$REPO_PATCHES"/README.md "$PATCHES_DIR/" 2>/dev/null || true
chmod +x "$PATCHES_DIR"/*.sh 2>/dev/null || true
success "Patches copied: $(ls "$PATCHES_DIR"/*.sh 2>/dev/null | wc -l) patch(es)"

info "Copying assets from repo..."
if [ -d "$REPO_ASSETS" ]; then
    cp "$REPO_ASSETS"/* "$PATCHES_DIR/" 2>/dev/null || true
    success "Assets copied (favicon.ico, favicon.png, etc.)"
else
    warn "No assets directory found in repo"
fi
echo ""

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
# STEP 9: Apply all patches
# ============================================================
echo ""
info "Applying patches from $PATCHES_DIR ..."

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
# STEP 10: Rebuild after patches (patches modify source)
# ============================================================
echo ""
info "Rebuilding UI after patches..."
cd "$CS_UI_DIR"
pnpm build

if [ ! -f "$CS_UI_DIR/dist/index.html" ]; then
    error "Post-patch build failed."
    exit 1
fi

# Copy favicon to dist if it exists
if [ -f "$CS_UI_DIR/public/cyberdine-icon.png" ]; then
    cp "$CS_UI_DIR/public/cyberdine-icon.png" "$CS_UI_DIR/dist/" 2>/dev/null || true
fi

success "Final build complete"

# ============================================================
# STEP 11: Create helper scripts
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
    # Copy favicon if present
    [ -f "$SCRIPT_DIR/public/cyberdine-icon.png" ] && cp "$SCRIPT_DIR/public/cyberdine-icon.png" "$SCRIPT_DIR/dist/" 2>/dev/null || true
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

# --- apply_patches.sh ---
cat > "$CS_UI_DIR/apply_patches.sh" << APPLYPATCH_EOF
#!/usr/bin/env bash
# Re-apply all patches without full setup.
# Run after a freqtrade update, then rebuild.sh
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
if [ "\$COUNT" -eq 0 ]; then
    echo "[INFO] No patches found."
else
    echo "[OK] Applied \$COUNT patch(es). Run rebuild.sh then restart freqtrade."
fi
APPLYPATCH_EOF
chmod +x "$CS_UI_DIR/apply_patches.sh"

# ============================================================
# Save config for update.sh
# ============================================================
CONFIG_FILE="$REPO_DIR/.cyberdine_config"
cat > "$CONFIG_FILE" << CONFIGEOF
USER_DATA_DIR=$USER_DATA_DIR
FT_PACKAGE_DIR=$FT_PACKAGE_DIR
CONFIGEOF
success "Config saved to $CONFIG_FILE"

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
echo "    apply_patches.sh  - Re-apply patches after freqtrade update"
echo ""
echo -e "  ${YELLOW}After a freqtrade update:${NC}"
echo "    cd $CS_UI_DIR"
echo "    ./relink.sh && ./apply_patches.sh && ./rebuild.sh"
echo "    (then restart freqtrade)"
echo ""
echo -e "  ${YELLOW}Restart FreqTrade now for backend patches to take effect.${NC}"
echo ""
echo -e "  ${RED}DO NOT run 'freqtrade install-ui' — use relink.sh instead.${NC}"
echo ""
