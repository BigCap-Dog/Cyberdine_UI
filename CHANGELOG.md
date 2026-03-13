# Changelog

## v1.3.5 — 2026-03-13

new scoring system, enhanced tables and charts, visual enhancements


## v1.2.0 — 2026-03-13

Performance Tab- added more stats, updated phase changes


## v1.0.1 — 2026-03-11

### Fixes
- **update.sh cleanup** — properly removes API route decorators + functions + orphan lines during clean cycle
- **Performance endpoint** — fixed duplicate route insertion causing 422 errors
- **Nav order** — Dashboard → Trade → Performance → Chart → Logs
- **Active tab styling** — bright cyan highlight with dark bold text, uppercase labels
- **Pair breakdown table** — top section of Performance page shows per-pair stats (clickable to filter charts + trade list)
- **Trade table** — 20 per page, bold uppercase centered headers, stake amount column

## v1.0.0 — 2026-03-11

Initial release.

### Features
- **Cyberdine Dark Theme** — deep space color palette, electric cyan accents, IBM Plex Sans + JetBrains Mono fonts
- **Custom Branding** — Cyberdine Strategies logo, favicon, nav bar, home page
- **Live Candle** — real-time candle updates on chart via `/pair_candles/live` backend endpoint (zero exchange API calls)
- **Performance Dashboard** — model confidence vs profit analysis with:
  - Per-pair breakdown table (clickable to filter charts + trade list)
  - Confidence vs Profit scatter chart
  - Peak vs Close scatter chart
  - Trade Journey bar chart (peak/close/trough per trade)
  - Confidence Distribution histogram with win rate overlay
  - Paginated trade details table (20/page) with stake amount column

### Infrastructure
- Patch-based overlay system — clean separation from upstream FreqUI
- `setup.sh` — one-command install on new rigs
- `update.sh` — clean uninstall + fresh re-apply cycle (picks up upstream FreqUI + FreqTrade changes)
- GitHub deployment for multi-rig management
- Helper scripts: `rebuild.sh`, `relink.sh`, `apply_patches.sh`

### Patches
| Patch | Description |
|-------|-------------|
| `00_cyberdine_skin.sh` | Dark theme, branding, colors, fonts, logos, nav styling |
| `01_live_candle.sh` | Live candle endpoint + frontend polling |
| `02_performance_dashboard.sh` | Performance page with pair breakdown + bulk DB queries |
