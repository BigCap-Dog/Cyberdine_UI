# Cyberdine Strategies UI

Custom FreqUI overlay for Cyberdine Strategies RL trading rigs.

Clones the official FreqUI, applies custom theme + feature patches, builds, and symlinks into FreqTrade.

## Quick Install (new rig)
```bash
git clone https://github.com/BigCap-Dog/Cyberdine_UI.git
cd Cyberdine_UI
chmod +x setup.sh
./setup.sh
```

When prompted, enter your `user_data` path (e.g. `/home/freq/freqtrade/user_data`).

## Update (existing rig)
```bash
cd ~/freqtrade/user_data/cs_ui

# Pull latest patches
cd ~/Cyberdine_UI && git pull

# Copy updated patches + assets
cp patches/*.sh ~/freqtrade/user_data/cs_ui/patches/
cp assets/* ~/freqtrade/user_data/cs_ui/patches/

# Re-apply and rebuild
cd ~/freqtrade/user_data/cs_ui
./apply_patches.sh
./rebuild.sh
```

Then restart FreqTrade for backend patches.

## After a FreqTrade Update
```bash
cd ~/freqtrade/user_data/cs_ui
./relink.sh            # Restore symlink
./apply_patches.sh     # Re-apply backend patches
./rebuild.sh           # Rebuild frontend
# Restart freqtrade
```

## Patches

| Patch | Description |
|-------|-------------|
| `00_cyberdine_skin.sh` | Dark console theme, branding, colors, fonts, logos |
| `01_live_candle.sh` | Live candle on chart (backend + frontend) |
| `02_performance_dashboard.sh` | Model performance page with charts + paginated table |

## Adding a New Patch

1. Create `patches/03_my_feature.sh`
2. Use `$FT_PACKAGE_DIR` and `$CS_UI_DIR` env vars
3. Make it idempotent (check before patching)
4. Test: `./apply_patches.sh && ./rebuild.sh`
5. Commit and push

## DO NOT run `freqtrade install-ui` — it will overwrite the symlink. Use `relink.sh` instead.
