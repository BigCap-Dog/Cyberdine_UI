# Cyberdine Strategies UI

Custom FreqUI overlay for Cyberdine Strategies RL trading rigs.

Clones the official FreqUI, applies custom dark theme + feature patches, builds, and symlinks into FreqTrade.

---

## Prerequisites

- FreqTrade installed and running
- Linux (Ubuntu/Debian tested)
- Git installed

Node.js and pnpm will be installed automatically if not present.

---

## Fresh Install (new rig)

```bash
cd ~
git clone https://github.com/BigCap-Dog/Cyberdine_UI.git
cd Cyberdine_UI
chmod +x setup.sh update.sh
./setup.sh
```

When prompted, enter the full path to your FreqTrade `user_data` directory, e.g.:
```
/home/freq/freqtrade/user_data
```

The script will automatically:
1. Install Node.js + pnpm (if needed)
2. Clone FreqUI into `user_data/cs_ui/`
3. Copy all patches and assets (logos, favicons)
4. Build the UI
5. Symlink it into FreqTrade
6. Apply all backend + frontend patches
7. Rebuild with patches applied

**Restart FreqTrade** after setup for backend patches to take effect.

---

## Update (existing rig)

```bash
cd ~/Cyberdine_UI
./update.sh
```

That's it. The script pulls latest changes, copies patches + assets, applies them, and rebuilds.

Then restart FreqTrade.

---

## After a FreqTrade Update

FreqTrade updates may overwrite the UI symlink and backend patches. To restore:

```bash
cd ~/freqtrade/user_data/cs_ui
./relink.sh && ./apply_patches.sh && ./rebuild.sh
```

Then restart FreqTrade.

**DO NOT run `freqtrade install-ui`** — use `relink.sh` instead.

---

## Patches

| Patch | Type | Description |
|-------|------|-------------|
| `00_cyberdine_skin.sh` | Frontend | Dark console theme, Cyberdine branding, custom colors, fonts, logos |
| `01_live_candle.sh` | Both | Live candle on chart — adds `/pair_candles/live` backend endpoint + frontend polling |
| `02_performance_dashboard.sh` | Both | Model performance page — confidence vs profit charts, paginated trade table |

---

## Helper Scripts (in `cs_ui/` after setup)

| Script | Purpose |
|--------|---------|
| `rebuild.sh` | Rebuild UI after patch changes |
| `relink.sh` | Restore symlink after FreqTrade update |
| `apply_patches.sh` | Re-apply backend patches after FreqTrade update |

---

## Adding a New Patch

1. Create `patches/03_my_feature.sh`
2. Use `$FT_PACKAGE_DIR` and `$CS_UI_DIR` env vars
3. Make it idempotent (check before patching with `grep -q`)
4. Test locally:
```bash
cd ~/freqtrade/user_data/cs_ui
./apply_patches.sh && ./rebuild.sh
```
5. Add to repo:
```bash
cd ~/Cyberdine_UI
cp ~/freqtrade/user_data/cs_ui/patches/03_my_feature.sh patches/
git add -A && git commit -m "Add patch: my feature" && git push
```

---

## Troubleshooting

**UI not loading:** Check symlink: `ls -la ~/freqtrade/freqtrade/rpc/api_server/ui/installed` — should point to `cs_ui/dist`. Run `./relink.sh` if broken.

**Backend patches not working:** Restart FreqTrade after applying patches.

**Performance page timeout:** Ensure latest `02_performance_dashboard.sh` (bulk query version).

**Favicon not showing:** Hard refresh `Ctrl+Shift+R` or try incognito window.

---

## First Time Updating (if installed before update.sh existed)

If your rig was set up before `update.sh` was added to the repo:
```bash
cd ~/Cyberdine_UI
git pull
chmod +x update.sh
./update.sh
```

After this, future updates are just `./update.sh`.
