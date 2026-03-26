# Changelog

## v1.4.06 — 2026-03-26

v10.6 phase support — developing, preserve1/2, trailing1/2, stop-loss inference

### Changes
-Phase column updated for v10.6 strategy phases: developing (grey), preserve1/2 (yellow), tra>
-Closed trades show last phase before exit, inferred from exit_tag prefix
-Trades stopped out in developing phase show "Stop-Loss" (red bg, black font)
-Legacy v10/v10.5 phase colors preserved for older trades
-Updated pnpm to latest 


## v1.4.05 — 2026-03-17

updated push notation

### Changes
-updated push script  to include detailed notation 
- 
- 


## v1.4.0 — 2026-03-17

Confidence charts zoomed to 90-100% with 1% buckets for higher resolution. Peak/left/valley columns color coded across both tables (peak: red<0 yellow<5% green>5%, left: green<5% yellow<10% red>10%, valley: green/red by sign). ALL PAIRS avg peak now computed. Phase column infers pre-exit state — Trailing_Win (green) for winners, Trailing_Loss (red) for losers. Trough renamed to Valley. Bottom table syncs with top table trade limit toggle.
-Confidence charts zoomed to 90-100% with 1% resolution buckets
-Avg Peak colors: red <0%, yellow 0-5%, green >5% (both tables + ALL PAIRS)
-Avg Left colors: green 0-5%, yellow 5-10%, red >10% (both tables)
-Left on table in trade details: same color coding as pair breakdown
-ALL PAIRS avg peak now shows actual average instead of "—"
-Bottom table syncs with top table trade limit toggle
-Phase renamed: RL_Exit infers pre-exit state (Trailing_Win / Trailing_Loss)
-Loss_Mitigation → Trailing_Loss (red), Trailing → Trailing_Win (green)
-Trough column renamed to Valley, positive values show green
-Peak column: red <0%, yellow 0-5%, green >5%

## v1.3.96 — 2026-03-15

Fix pair table toggles, open trade unrealized PnL from live candle data, avg peak negative color


## v1.3.95 — 2026-03-14

Skin fixes: black text on active nav tabs and selected pair list, improved contrast for primary highlights and surface text


## v1.3.9 — 2026-03-14

Performance dashboard v2: pair scoring system with pack tightness, exit efficiency (1-left/peak), confidence calibration chart, avg/total $ from actual PnL, chart toggles (All/100/50/10), open trades show unrealized PnL, 6 phase colors, 25% larger fonts, 20% taller charts, trade journey most recent on right


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
