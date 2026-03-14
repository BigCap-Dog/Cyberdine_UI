# Cyberdine Strategies UI  `v1.3.9`

Custom FreqUI overlay for Cyberdine Strategies RL trading rigs.

Clones the official FreqUI, applies custom dark theme + feature patches, builds, and symlinks into FreqTrade. Designed for multi-rig deployment via GitHub.

---

## What's Included

| Feature | Description |
|---------|-------------|
| **Dark Console Theme** | Deep space color palette, electric cyan accents, custom fonts |
| **Branding** | Cyberdine Strategies logo, favicon, nav bar, home page |
| **Live Candle** | Real-time candle on chart (reads from in-memory cache, zero exchange API calls) |
| **Performance Dashboard** | Per-pair breakdown, confidence vs profit charts, paginated trade table |
| **Clean Update System** | Full uninstall + re-apply on every update — always picks up upstream changes |

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

When prompted, enter the full path to your FreqTrade `user_data` directory:
```
/home/freq/freqtrade/user_data
```

**Restart FreqTrade** after setup for backend patches to take effect.

---

## Update (any rig)

```bash
cd ~/Cyberdine_UI
./update.sh
```

That's it. The update script:
1. Pulls latest patches from GitHub
2. Removes all backend patches from FreqTrade Python files
3. Resets cs_ui to clean upstream FreqUI
4. Copies patches + assets
5. Applies all patches fresh
6. Rebuilds

Then restart FreqTrade.

---

## After a FreqTrade Update

Same command:
```bash
cd ~/Cyberdine_UI
./update.sh
```

The clean update cycle handles everything — symlink, backend patches, frontend rebuild.

**DO NOT run `freqtrade install-ui`** — use `update.sh` or `relink.sh` instead.

---

## First Time Updating (rigs installed before `update.sh` existed)

```bash
cd ~/Cyberdine_UI
git pull
chmod +x update.sh
./update.sh
```

---

## Patches

| Patch | Type | Description |
|-------|------|-------------|
| `00_cyberdine_skin.sh` | Frontend | Dark theme, branding, colors, fonts, logos, nav styling |
| `01_live_candle.sh` | Both | Live candle via `/pair_candles/live` endpoint + frontend polling |
| `02_performance_dashboard.sh` | Both | Performance page — pair breakdown, charts, paginated trade table |

---

## Helper Scripts (in `cs_ui/` after setup)

| Script | Purpose |
|--------|---------|
| `rebuild.sh` | Rebuild UI only (no backend changes) |
| `relink.sh` | Restore symlink if broken |
| `apply_patches.sh` | Re-apply patches without full update cycle |

---

## Adding a New Patch

1. Create `patches/03_my_feature.sh`
2. Use `$FT_PACKAGE_DIR` and `$CS_UI_DIR` env vars
3. Make it idempotent (check before patching with `grep -q`)
4. Test: `cd ~/Cyberdine_UI && ./update.sh`
5. Push:
```bash
cd ~/Cyberdine_UI
git add -A && git commit -m "Add patch: my feature" && git push
```

---

## Uninstall (restore default FreqUI)

```bash
cd ~/Cyberdine_UI
./uninstall.sh
```

This will:
1. Remove all backend patches from FreqTrade Python files
2. Delete the cs_ui directory
3. Remove the custom UI symlink
4. Restore default FreqUI (from backup or via `freqtrade install-ui`)

Then restart FreqTrade. To reinstall later, just run `./setup.sh` again.

---

## Versioning

See [CHANGELOG.md](CHANGELOG.md) for release history.

Current version is stored in `VERSION`.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| UI not loading | Check symlink: `ls -la ~/freqtrade/freqtrade/rpc/api_server/ui/installed` |
| Backend not working | Restart FreqTrade after `./update.sh` |
| Performance timeout | Ensure latest patch (bulk query version) — run `./update.sh` |
| Favicon not showing | Hard refresh `Ctrl+Shift+R` or incognito window |
| Stale patches | `./update.sh` does a full clean cycle — fixes everything |
