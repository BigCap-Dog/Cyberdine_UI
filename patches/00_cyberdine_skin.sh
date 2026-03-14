#!/usr/bin/env bash
# ============================================================
# Patch 00: Cyberdine Strategies Skin
#
# FRONTEND ONLY — no backend changes.
#
# Applies the dark console theme, custom branding, logo, favicon,
# and font changes to the FreqUI fork.
#
# - Deep space color palette (#030508 → #070b10 → #0a0f16)
# - Electric cyan primary (#00d4ff)
# - Brighter profit/loss colors (#00e69d / #ff4757)
# - IBM Plex Sans + JetBrains Mono fonts
# - Cyberdine Strategies branding throughout
# - Dark navbar background
# ============================================================
set -euo pipefail

TAILWIND_FILE="$CS_UI_DIR/src/styles/tailwind.css"
COLORS_FILE="$CS_UI_DIR/src/stores/colors.ts"
APP_FILE="$CS_UI_DIR/src/App.vue"
NAVBAR_FILE="$CS_UI_DIR/src/components/layout/NavBar.vue"
BODY_FILE="$CS_UI_DIR/src/components/layout/BodyLayout.vue"
INDEX_FILE="$CS_UI_DIR/index.html"
HOME_FILE="$CS_UI_DIR/src/views/HomeView.vue"

# ── TAILWIND: Color palette + dark theme ──
echo "  [00] Patching tailwind.css (color palette)..."
if grep -q "Rig1 deep space surfaces" "$TAILWIND_FILE"; then
    echo "    Already patched, skipping."
else
    python3 -c "
filepath = '$TAILWIND_FILE'
with open(filepath, 'r') as f:
    content = f.read()

# Replace primary color palette
content = content.replace(
    '--p-primary-50: #DBFAFF;',
    '--p-primary-50: #E0F7FF;'
).replace(
    '--p-primary-100: #B8F4FF;',
    '--p-primary-100: #B3ECFF;'
).replace(
    '--p-primary-200: #75EAFF;',
    '--p-primary-200: #80DFFF;'
).replace(
    '--p-primary-300: #2EE0FF;',
    '--p-primary-300: #4DD2FF;'
).replace(
    '--p-primary-400: #00C3E6;',
    '--p-primary-400: #1AC5FF;'
).replace(
    '--p-primary-500: #0089A1;',
    '--p-primary-500: #00B4E6;'
).replace(
    '--p-primary-600: #006C80;',
    '--p-primary-600: #0098C2;'
).replace(
    '--p-primary-700: #005261;',
    '--p-primary-700: #007A9E;'
).replace(
    '--p-primary-800: #003842;',
    '--p-primary-800: #005C7A;'
).replace(
    '--p-primary-900: #001A1F;',
    '--p-primary-900: #003E56;'
).replace(
    '--p-primary-950: #000D0F;',
    '--p-primary-950: #002030;'
).replace(
    '--p-primary-color: var(--p-primary-600);',
    '--p-primary-color: var(--p-primary-400);'
)

# Replace profit/loss colors
content = content.replace('--color-profit: #12bb7b;', '--color-profit: #00e69d;')
content = content.replace('--color-loss: #ef5350;', '--color-loss: #ff4757;')

# Replace dark theme block
old_dark = '''  .ft-dark-theme {
      --p-content-background: var(--p-surface-950);
      --p-menu-background: var(--p-surface-900);

      --p-primary-contrast-color: var(--p-text-200);
      --p-button-secondary-background: var(--p-surface-700);
      --p-button-secondary-hover-background: var(--p-surface-600);
  }'''

new_dark = '''  .ft-dark-theme {
      --p-content-background: #070b10;
      --p-menu-background: #0a0f16;

      --p-primary-contrast-color: #030508;
      --p-button-secondary-background: #161e2b;
      --p-button-secondary-hover-background: #1e2836;

      /* Rig1 deep space surfaces */
      --p-surface-0: #e8edf4;
      --p-surface-50: #c8d1de;
      --p-surface-100: #9bafc8;
      --p-surface-200: #6b7f96;
      --p-surface-300: #4a5f78;
      --p-surface-400: #354a60;
      --p-surface-500: #2a3545;
      --p-surface-600: #1e2836;
      --p-surface-700: #161e2b;
      --p-surface-800: #0f1520;
      --p-surface-900: #0a0f16;
      --p-surface-950: #070b10;
  }'''

content = content.replace(old_dark, new_dark)

# Add body background for dark mode
old_html = '''html {
    /*  Set the default font size to 14px */
    font-size: 14px;
}'''

new_html = '''html {
    /*  Set the default font size to 14px */
    font-size: 14px;
}

html.ft-dark-theme, .ft-dark-theme body {
    background-color: #030508;
}

/* ── Cyberdine UI overrides ── */

/* Selected pair in trade page pair list — teal bg, visible text */
.ft-dark-theme .p-listbox-option[data-p-selected="true"],
.ft-dark-theme .p-listbox-option.p-focus,
.ft-dark-theme .p-listbox-option[aria-selected="true"] {
    background-color: rgba(0, 180, 230, 0.15) !important;
    border-left: 3px solid #00d4ff !important;
}

/* Active/selected items in any list — ensure contrast */
.ft-dark-theme .p-highlight {
    background-color: rgba(0, 180, 230, 0.12) !important;
    color: #e8edf4 !important;
}

/* Primary button and badge backgrounds — ensure dark text on bright bg */
.ft-dark-theme .bg-primary-500,
.ft-dark-theme .bg-primary-400 {
    color: #030508 !important;
}

/* Active nav tab — force black bold text on cyan */
.ft-dark-theme a.bg-\[\#00d4ff\],
.ft-dark-theme .router-link-active.bg-\[\#00d4ff\] {
    color: #000000 !important;
    font-weight: 900 !important;
}

/* Fix washed out text in surface areas */
.ft-dark-theme .text-surface-400 {
    color: #8899aa !important;
}
.ft-dark-theme .text-surface-300 {
    color: #a0b0c0 !important;
}'''

content = content.replace(old_html, new_html)

with open(filepath, 'w') as f:
    f.write(content)
print('    Done.')
"
fi

# ── COLORS STORE: Profit/loss + candle colors ──
echo "  [00] Patching colors.ts..."
if grep -q "#00e69d" "$COLORS_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i "s/colorUp: '#26A69A'/colorUp: '#00e69d'/" "$COLORS_FILE"
    sed -i "s/colorDown: '#EF5350'/colorDown: '#ff4757'/" "$COLORS_FILE"
    sed -i "s/colorProfit: '#12bb7b'/colorProfit: '#00e69d'/" "$COLORS_FILE"
    sed -i "s/colorLoss: '#ef5350'/colorLoss: '#ff4757'/" "$COLORS_FILE"
    sed -i "s/\['#26A69A', '#ef5350'\]/['#00e69d', '#ff4757']/" "$COLORS_FILE"
    echo "    Done."
fi

# ── APP.VUE: Font family ──
echo "  [00] Patching App.vue (font)..."
if grep -q "IBM Plex Sans" "$APP_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i "s/font-family: Avenir, Helvetica, Arial, sans-serif;/font-family: 'IBM Plex Sans', -apple-system, BlinkMacSystemFont, sans-serif;/" "$APP_FILE"
    echo "    Done."
fi

# ── NAVBAR: Dark background + branding + nav order + active tab style ──
echo "  [00] Patching NavBar.vue (branding + styling)..."
if grep -q "Cyberdine Strategies" "$NAVBAR_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i 's/bg-primary-500/bg-\[#070b10\] border-\[#1a2332\]/' "$NAVBAR_FILE"
    sed -i 's/Freqtrade UI/Cyberdine Strategies/' "$NAVBAR_FILE"
    sed -i "s/let title = 'freqUI'/let title = 'Cyberdine Strategies'/" "$NAVBAR_FILE"

    # Reorder nav items: Dashboard first, then Trade, then rest
    # And style active links with bright blue bg, dark bold text
    python3 -c "
with open('$NAVBAR_FILE', 'r') as f:
    content = f.read()

# Replace the active-class on nav links for bright blue highlight style
content = content.replace(
    'active-class=\"underline\"',
    'active-class=\"bg-[#00d4ff] text-[#000000] font-black rounded px-2 no-underline\"'
)

# Reorder: move Dashboard before Trade
# Find the Trade nav item and Dashboard nav item, swap their order
old_order = '''  {
    label: 'Trade',
    to: '/trade',
    visible: computed(() => !botStore.canRunBacktest),
    icon: 'i-mdi-currency-usd',
  },
  {
    label: 'Dashboard',
    to: '/dashboard',
    visible: computed(() => !botStore.canRunBacktest),
    icon: 'i-mdi-view-dashboard',
  },'''

new_order = '''  {
    label: 'Dashboard',
    to: '/dashboard',
    visible: computed(() => !botStore.canRunBacktest),
    icon: 'i-mdi-view-dashboard',
  },
  {
    label: 'Trade',
    to: '/trade',
    visible: computed(() => !botStore.canRunBacktest),
    icon: 'i-mdi-currency-usd',
  },'''

content = content.replace(old_order, new_order)

# Make nav link text uppercase and slightly larger
content = content.replace(
    'class=\"text-surface-200 flex items-center gap-2\"',
    'class=\"text-surface-200 flex items-center gap-2 uppercase text-sm font-semibold tracking-wide py-1 px-2 rounded transition-all\"'
)

with open('$NAVBAR_FILE', 'w') as f:
    f.write(content)
print('    Done.')
"
fi

# ── BODY LAYOUT: Background ──
echo "  [00] Patching BodyLayout.vue..."
if grep -q "#030508" "$BODY_FILE"; then
    echo "    Already patched, skipping."
else
    cat > "$BODY_FILE" << 'BODYEOF'
<template>
  <main class="dark:bg-[#030508]">
    <RouterView />
  </main>
</template>
BODYEOF
    echo "    Done."
fi

# ── INDEX.HTML: Title + font imports ──
echo "  [00] Patching index.html (title + fonts)..."
if grep -q "Cyberdine Strategies" "$INDEX_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i 's/<title>FreqUI<\/title>/<title>⚡ Cyberdine Strategies<\/title>/' "$INDEX_FILE"
    # Add font imports before </head>
    sed -i '/<\/head>/i\  <link rel="preconnect" href="https:\/\/fonts.googleapis.com">\n  <link rel="preconnect" href="https:\/\/fonts.gstatic.com" crossorigin>\n  <link href="https:\/\/fonts.googleapis.com\/css2?family=IBM+Plex+Sans:wght@400;500;600;700\&family=JetBrains+Mono:wght@400;500;700\&display=swap" rel="stylesheet">' "$INDEX_FILE"
    echo "    Done."
fi

# ── HOME VIEW: Branding ──
echo "  [00] Patching HomeView.vue..."
if grep -q "Cyberdine Strategies" "$HOME_FILE"; then
    echo "    Already patched, skipping."
else
    python3 -c "
with open('$HOME_FILE', 'r') as f:
    content = f.read()

# Replace mask-based logo with regular img
content = content.replace(
    'title=\"Freqtrade logo\"',
    'title=\"Cyberdine Strategies logo\"'
)
content = content.replace(
    'Welcome to the Freqtrade UI',
    'Welcome to Cyberdine Strategies'
)
content = content.replace(
    'Have fun - <i>wishes you the Freqtrade team</i>',
    'Autonomous RL Trading \u00b7 <i>Rig1 Online</i>'
)

# Replace CSS mask div with regular img tag
old_div = '''    <div
      title=\"Cyberdine Strategies logo\"
      class=\"logo-svg my-5 mx-auto dark:bg-white bg-black sm:w-[250px] sm:h-[250px] w-[150px] h-[150px] transition-all duration-300\"
    />'''
new_div = '''    <div class=\"flex justify-center my-5\">
      <img
        src=\"@/assets/freqtrade-logo.png\"
        alt=\"Cyberdine Strategies logo\"
        class=\"sm:w-[250px] sm:h-[250px] w-[150px] h-[150px] object-contain transition-all duration-300\"
      />
    </div>'''

if old_div in content:
    content = content.replace(old_div, new_div)
    # Remove the mask CSS style block
    import re
    content = re.sub(r'<style[^>]*>.*?</style>', '', content, flags=re.DOTALL)

with open('$HOME_FILE', 'w') as f:
    f.write(content)
print('    Done.')
"
fi

# ── FAVICON + LOGO: Copy from patches directory ──
PATCHES_DIR="$CS_UI_DIR/patches"
echo "  [00] Setting up favicon and logo..."

# Look for favicon files in patches/ directory
FAVICON_ICO=""
FAVICON_PNG=""
for search_dir in "$PATCHES_DIR" "$CS_UI_DIR"; do
    [ -z "$FAVICON_ICO" ] && [ -f "$search_dir/favicon.ico" ] && FAVICON_ICO="$search_dir/favicon.ico"
    [ -z "$FAVICON_PNG" ] && [ -f "$search_dir/favicon.png" ] && FAVICON_PNG="$search_dir/favicon.png"
    [ -z "$FAVICON_ICO" ] && [ -f "$search_dir/cyberdine-favicon.ico" ] && FAVICON_ICO="$search_dir/cyberdine-favicon.ico"
    [ -z "$FAVICON_PNG" ] && [ -f "$search_dir/cyberdine-favicon.png" ] && FAVICON_PNG="$search_dir/cyberdine-favicon.png"
done

if [ -n "$FAVICON_ICO" ]; then
    cp "$FAVICON_ICO" "$CS_UI_DIR/public/favicon.ico"
    echo "    Copied favicon.ico from $FAVICON_ICO"
else
    echo "    No favicon.ico found in patches/ or cs_ui/"
fi

if [ -n "$FAVICON_PNG" ]; then
    cp "$FAVICON_PNG" "$CS_UI_DIR/src/assets/freqtrade-logo.png"
    cp "$FAVICON_PNG" "$CS_UI_DIR/src/assets/freqtrade-logo-mask.png"
    echo "    Copied logo PNG from $FAVICON_PNG"

    # Create a small version for the browser tab favicon
    if command -v convert &>/dev/null; then
        convert "$FAVICON_PNG" -resize 64x64 "$CS_UI_DIR/public/cyberdine-icon.png"
        echo "    Created resized 64x64 favicon PNG"
    else
        cp "$FAVICON_PNG" "$CS_UI_DIR/public/cyberdine-icon.png"
        echo "    Copied full-size PNG as favicon (install imagemagick for resize)"
    fi

    # Update favicon reference to PNG with cache buster
    if ! grep -q "cyberdine-icon.png" "$INDEX_FILE"; then
        sed -i 's|<link rel="icon" href="/favicon.ico">|<link rel="icon" type="image/png" href="/cyberdine-icon.png?v=2">|' "$INDEX_FILE"
        echo "    Updated index.html favicon reference"
    fi
else
    echo "    No favicon.png found in patches/ or cs_ui/"
fi

echo "  [00] Cyberdine Strategies skin patch complete."