#!/usr/bin/env bash
# ============================================================
# Patch 02: Performance Dashboard
#
# BACKEND:  Adds /performance/model endpoint (bulk DB query, no N+1)
# FRONTEND: PerformanceView.vue + router + navbar entry
#           - Paginated table (20 trades per page)
#           - Bold uppercase centered headers, larger font
#           - Stake amount column
#
# Uses Python for JS file insertions to avoid sed { brace issues.
# ============================================================
set -euo pipefail

RPC_FILE="$FT_PACKAGE_DIR/rpc/rpc.py"
API_FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"
VIEWS_DIR="$CS_UI_DIR/src/views"
ROUTER_FILE="$CS_UI_DIR/src/router/index.ts"
NAVBAR_FILE="$CS_UI_DIR/src/components/layout/NavBar.vue"

# ── BACKEND: rpc.py — bulk query version ──
echo "  [02] Patching rpc.py (model performance)..."
if grep -q "_rpc_model_performance" "$RPC_FILE"; then
    echo "    Already patched, skipping."
else
    # Use Python for the complex insertion to avoid sed escaping hell
    python3 << PYEOF
import re

with open("$RPC_FILE", "r") as f:
    content = f.read()

method_code = '''
    def _rpc_model_performance(self) -> dict[str, Any]:
        """
        Return model confidence vs trade performance analysis.
        Uses bulk queries to avoid N+1 DB connection exhaustion.
        Zero exchange calls — database only.
        """
        from freqtrade.persistence import Trade
        from freqtrade.persistence.models import _CustomData
        import re as _re

        # Bulk fetch all trades in one query
        trades_raw = Trade.session.query(Trade).all()

        # Bulk fetch ALL custom data in one query, keyed by trade_id
        custom_data_rows = Trade.session.query(_CustomData).all()
        custom_map: dict[int, dict[str, str]] = {}
        for cd in custom_data_rows:
            if cd.ft_trade_id not in custom_map:
                custom_map[cd.ft_trade_id] = {}
            custom_map[cd.ft_trade_id][cd.cd_key] = cd.cd_value

        results = []
        for t in trades_raw:
            prob = 0.0
            direction = "long"
            if t.enter_tag:
                m = _re.search(r"RL_(Long|Short)_P(\\d+)", t.enter_tag)
                if m:
                    direction = m.group(1).lower()
                    prob = int(m.group(2)) / 100.0

            # Read custom data from bulk map instead of per-trade queries
            t_custom = custom_map.get(t.id, {})
            pk_str = t_custom.get("pk")
            lw_str = t_custom.get("lw")
            sl_phase = t_custom.get("sl_phase")
            exit_tag = t_custom.get("exit_tag")

            try:
                peak_profit = float(pk_str) if pk_str else None
            except (ValueError, TypeError):
                peak_profit = None
            try:
                trough_profit = float(lw_str) if lw_str else None
            except (ValueError, TypeError):
                trough_profit = None

            close_profit = float(t.close_profit) if t.close_profit else None
            close_profit_abs_val = float(t.close_profit_abs) if t.close_profit_abs is not None else None

            open_rate = float(t.open_rate) if t.open_rate else 0
            close_rate = float(t.close_rate) if t.close_rate else None
            max_rate = float(t.max_rate) if t.max_rate else None
            min_rate = float(t.min_rate) if t.min_rate else None

            # For open trades, calculate unrealized profit from current rate
            if t.is_open and close_profit is None:
                try:
                    # Try to get current rate from dataprovider
                    dp = self._freqtrade.dataprovider
                    df = dp.ohlcv(t.pair, self._freqtrade.config.get('timeframe', '5m'))
                    if df is not None and not df.empty:
                        current_rate = float(df.iloc[-1]['close'])
                    else:
                        current_rate = max_rate  # fallback
                    if current_rate and current_rate > 0:
                        close_profit = t.calc_profit_ratio(current_rate)
                        if hasattr(t, 'calculate_profit'):
                            close_profit_abs_val = float(t.calculate_profit(current_rate).profit_abs)
                except Exception:
                    pass

            max_potential = None
            if max_rate and open_rate > 0:
                if direction == "long":
                    max_potential = (max_rate - open_rate) / open_rate
                else:
                    max_potential = (open_rate - min_rate) / open_rate if min_rate else None

            left_on_table = None
            if peak_profit is not None and close_profit is not None:
                left_on_table = peak_profit - close_profit

            drawdown_from_peak = None
            if peak_profit is not None and trough_profit is not None:
                drawdown_from_peak = peak_profit - trough_profit

            duration_mins = None
            if t.close_date and t.open_date:
                duration_mins = int((t.close_date - t.open_date).total_seconds() / 60)

            results.append({
                "id": t.id,
                "pair": t.pair,
                "direction": direction,
                "is_open": t.is_open,
                "model_confidence": prob,
                "enter_tag": t.enter_tag,
                "leverage": float(t.leverage) if t.leverage else 1.0,
                "stake_amount": float(t.stake_amount) if t.stake_amount else 0,
                "open_rate": open_rate,
                "close_rate": close_rate,
                "close_profit": close_profit,
                "close_profit_abs": close_profit_abs_val if close_profit_abs_val is not None else (float(close_profit * t.stake_amount * t.leverage) if close_profit and t.stake_amount else None),
                "max_rate": max_rate,
                "min_rate": min_rate,
                "max_potential_profit": max_potential,
                "peak_profit": peak_profit,
                "trough_profit": trough_profit,
                "left_on_table": left_on_table,
                "drawdown_from_peak": drawdown_from_peak,
                "sl_phase": sl_phase,
                "exit_tag": exit_tag,
                "exit_reason": t.exit_reason,
                "duration_mins": duration_mins,
                "open_date": str(t.open_date) if t.open_date else None,
                "close_date": str(t.close_date) if t.close_date else None,
            })

        closed = [r for r in results if not r["is_open"]]
        open_trades = [r for r in results if r["is_open"]]

        avg_confidence = sum(r["model_confidence"] for r in closed) / len(closed) if closed else 0
        avg_profit = sum(r["close_profit"] for r in closed if r["close_profit"] is not None) / len(closed) if closed else 0
        win_rate = len([r for r in closed if r["close_profit"] and r["close_profit"] > 0]) / len(closed) if closed else 0

        avg_left_on_table = 0
        lot_trades = [r for r in closed if r["left_on_table"] is not None]
        if lot_trades:
            avg_left_on_table = sum(r["left_on_table"] for r in lot_trades) / len(lot_trades)

        avg_drawdown = 0
        dd_trades = [r for r in closed if r["drawdown_from_peak"] is not None]
        if dd_trades:
            avg_drawdown = sum(r["drawdown_from_peak"] for r in dd_trades) / len(dd_trades)

        return {
            "trades": results,
            "summary": {
                "total_trades": len(results),
                "closed_trades": len(closed),
                "open_trades": len(open_trades),
                "avg_model_confidence": round(avg_confidence, 4),
                "avg_profit": round(avg_profit, 4),
                "win_rate": round(win_rate, 4),
                "avg_left_on_table": round(avg_left_on_table, 4),
                "avg_drawdown_from_peak": round(avg_drawdown, 4),
            },
        }
'''

# Insert before _ws_all_analysed_dataframes
anchor = "    def _ws_all_analysed_dataframes"
if anchor in content:
    content = content.replace(anchor, method_code + "\n" + anchor)
    with open("$RPC_FILE", "w") as f:
        f.write(content)
    print("    Done.")
else:
    print("    ERROR: Could not find anchor in rpc.py")
PYEOF
fi

# ── BACKEND: api_trading.py ──
echo "  [02] Patching api_trading.py (performance endpoint)..."
python3 - "$API_FILE" << 'PYEOF'
import sys

filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

if "def performance_model" in content:
    print("    Already patched, skipping.")
else:
    route = '''@router.get("/performance/model", tags=["Performance"])
def performance_model(rpc: RPC = Depends(get_rpc)):
    return rpc._rpc_model_performance()


'''
    # Insert before the /pair_candles GET route (the original FreqTrade one)
    anchor = '@router.get("/pair_candles", response_model=PairHistory'
    if anchor in content:
        content = content.replace(anchor, route + anchor, 1)
        with open(filepath, "w") as f:
            f.write(content)
        print("    Done.")
    else:
        print("    ERROR: anchor not found in api_trading.py")
PYEOF

# ── FRONTEND: PerformanceView.vue (always overwrite to get latest) ──
echo "  [02] Writing PerformanceView.vue..."
cat > "$VIEWS_DIR/PerformanceView.vue" << 'VUEEOF'
<script setup lang="ts">
import ECharts from 'vue-echarts';
import { BarChart, ScatterChart, LineChart } from 'echarts/charts';
import {
  GridComponent, TooltipComponent, LegendComponent, TitleComponent,
  DataZoomComponent, MarkLineComponent,
} from 'echarts/components';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';
import type { EChartsOption } from 'echarts';

use([
  BarChart, ScatterChart, LineChart, GridComponent, TooltipComponent,
  LegendComponent, TitleComponent, DataZoomComponent, MarkLineComponent, CanvasRenderer,
]);

const botStore = useBotStore();
const settingsStore = useSettingsStore();

interface TradePerf {
  id: number; pair: string; direction: string; is_open: boolean;
  model_confidence: number; enter_tag: string; leverage: number;
  stake_amount: number; open_rate: number; close_rate: number | null;
  close_profit: number | null; close_profit_abs: number | null; max_rate: number | null; min_rate: number | null;
  max_potential_profit: number | null; peak_profit: number | null;
  trough_profit: number | null; left_on_table: number | null;
  drawdown_from_peak: number | null; sl_phase: string | null;
  exit_tag: string | null; exit_reason: string | null;
  duration_mins: number | null; open_date: string | null; close_date: string | null;
}

interface PerfResponse {
  trades: TradePerf[];
  summary: {
    total_trades: number; closed_trades: number; open_trades: number;
    avg_model_confidence: number; avg_profit: number; win_rate: number;
    avg_left_on_table: number; avg_drawdown_from_peak: number;
  };
}

const perfData = ref<PerfResponse | null>(null);
const loading = ref(false);
const error = ref('');
const selectedPair = ref<string | null>(null); // null = ALL PAIRS

// Pagination state
const currentPage = ref(1);
const pageSize = 20;

async function fetchPerformance() {
  loading.value = true; error.value = '';
  try {
    const { api } = botStore.activeBot;
    const { data } = await api.get<PerfResponse>('/performance/model');
    perfData.value = data;
    currentPage.value = 1;
    selectedPair.value = null;
  } catch (e: any) {
    error.value = e?.message || 'Failed to load';
  } finally { loading.value = false; }
}

onMounted(() => fetchPerformance());

const theme = computed(() => settingsStore.chartTheme);

// Filtered trades based on selected pair
const filteredTrades = computed(() => {
  const all = perfData.value?.trades ?? [];
  if (!selectedPair.value) return all;
  return all.filter((t) => t.pair === selectedPair.value);
});

const closedTrades = computed(() => filteredTrades.value.filter((t) => !t.is_open));
const allTrades = computed(() => filteredTrades.value);

// Chart trade limit toggle (null = all trades)
const chartTradeLimit = ref<number | null>(null);
const chartTrades = computed(() => {
  const all = [...allTrades.value].reverse(); // most recent first
  if (chartTradeLimit.value === null) return all;
  return all.slice(0, chartTradeLimit.value);
});
const chartClosedTrades = computed(() => chartTrades.value.filter((t) => !t.is_open));

// Table trade limit toggle (null = all trades) — also drives charts when changed
const tableTradeLimit = ref<number | null>(null);
const packTightnessScore = ref(0);
const tableTrades = computed(() => {
  const all = perfData.value?.trades ?? [];
  if (tableTradeLimit.value === null) return all;
  const sorted = [...all].reverse();
  return sorted.slice(0, tableTradeLimit.value);
});

function setTableLimit(limit: number | null) {
  tableTradeLimit.value = limit;
  chartTradeLimit.value = limit; // sync charts with table
}

function setChartLimit(limit: number | null) {
  chartTradeLimit.value = limit; // charts only, don't touch table
}

// Per-pair stats aggregation
interface PairStat {
  pair: string;
  trades: number;
  open: number;
  winRate: number;
  avgProfit: number;
  avgProfitDollar: number;
  totalProfitDollar: number;
  avgConfidence: number;
  confToWinRate: number;
  confToProfitRatio: number;
  exitEfficiency: number;
  avgPeak: number;
  avgLeft: number;
  avgDrawdown: number;
  score: number;
}

const pairStats = computed((): PairStat[] => {
  const all = tableTradeLimit.value === null ? (perfData.value?.trades ?? []) : tableTrades.value;
  const pairMap: Record<string, TradePerf[]> = {};
  for (const t of all) {
    if (!pairMap[t.pair]) pairMap[t.pair] = [];
    pairMap[t.pair].push(t);
  }

  const stats: PairStat[] = Object.keys(pairMap).sort().map((pair) => {
    const trades = pairMap[pair];
    const closed = trades.filter((t) => !t.is_open);
    const openCount = trades.filter((t) => t.is_open).length;
    const wins = closed.filter((t) => t.close_profit && t.close_profit > 0).length;
    const winRate = closed.length > 0 ? wins / closed.length : 0;
    const avgProfit = closed.length > 0
      ? closed.reduce((s, t) => s + (t.close_profit ?? 0), 0) / closed.length : 0;
    const avgProfitDollar = closed.length > 0
      ? closed.reduce((s, t) => s + (t.close_profit_abs ?? 0), 0) / closed.length : 0;
    const avgConf = trades.length > 0
      ? trades.reduce((s, t) => s + t.model_confidence, 0) / trades.length : 0;

    // Confidence calibration: winRate / avgConfidence — 1.0 means perfect calibration
    const confToWinRate = avgConf > 0 ? winRate / avgConf : 0;
    // Confidence to profit: does high confidence translate to profit?
    const confToProfitRatio = avgConf > 0 ? winRate / avgConf : 0;

    const peakTrades = closed.filter((t) => t.peak_profit !== null);
    const avgPeak = peakTrades.length > 0
      ? peakTrades.reduce((s, t) => s + (t.peak_profit ?? 0), 0) / peakTrades.length : 0;
    const leftTrades = closed.filter((t) => t.left_on_table !== null);
    const avgLeft = leftTrades.length > 0
      ? leftTrades.reduce((s, t) => s + (t.left_on_table ?? 0), 0) / leftTrades.length : 0;

    // Exit efficiency: 1 - (avgLeft / avgPeak) — how much of peak profit was captured
    const exitEfficiency = avgPeak > 0 ? 1 - (avgLeft / avgPeak) : 0;

    const ddTrades = closed.filter((t) => t.drawdown_from_peak !== null);
    const avgDD = ddTrades.length > 0
      ? ddTrades.reduce((s, t) => s + (t.drawdown_from_peak ?? 0), 0) / ddTrades.length : 0;

    const totalProfitDollar = closed.reduce((s, t) => s + (t.close_profit_abs ?? 0), 0);

    return { pair, trades: trades.length, open: openCount, winRate, avgProfit, avgProfitDollar, totalProfitDollar, avgConfidence: avgConf, confToWinRate, confToProfitRatio, exitEfficiency, avgPeak, avgLeft, avgDrawdown: avgDD, score: 0 };
  });

  // ── Scoring system: rank each metric 1..N, sum for composite score ──
  const n = stats.length;
  if (n > 1) {
    // Columns to rank (higher = better, except avgLeft and avgDrawdown where lower = better)
    const higherBetter: (keyof PairStat)[] = ['trades', 'winRate', 'avgProfit', 'avgProfitDollar', 'totalProfitDollar', 'confToWinRate', 'exitEfficiency', 'avgPeak'];
    const lowerBetter: (keyof PairStat)[] = ['avgLeft', 'avgDrawdown'];

    function rankColumn(arr: PairStat[], key: keyof PairStat, ascending: boolean): number[] {
      const vals = arr.map((s, i) => ({ i, v: Number(s[key]) || 0 }));
      // Sort worst to best: ascending=true means lowest value is worst (for higher-is-better)
      vals.sort((a, b) => ascending ? a.v - b.v : b.v - a.v);
      const ranks = new Array(arr.length);
      const len = vals.length;
      for (let r = 0; r < len; r++) {
        // First in sorted order = worst = rank 1, last = best = rank N
        ranks[vals[r].i] = len - r;
      }
      return ranks;
    }

    const scoreAccum = new Array(n).fill(0);
    for (const key of higherBetter) {
      const ranks = rankColumn(stats, key, false);
      ranks.forEach((r, i) => scoreAccum[i] += r);
    }
    for (const key of lowerBetter) {
      const ranks = rankColumn(stats, key, true);
      ranks.forEach((r, i) => scoreAccum[i] += r);
    }

    // Convert to raw score sum (rank 1..N across each column, summed)
    stats.forEach((s, i) => s.score = scoreAccum[i]);

    // Sort by score descending (best at top)
    stats.sort((a, b) => b.score - a.score);
  }

  return stats;
});

const allPairsSummary = computed((): PairStat => {
  const s = perfData.value?.summary;
  const allClosed = (perfData.value?.trades ?? []).filter((t) => !t.is_open);
  const avgConf = s?.avg_model_confidence ?? 0;
  const winRate = s?.win_rate ?? 0;
  const confToWinRate = avgConf > 0 ? winRate / avgConf : 0;
  const avgProfitDollar = allClosed.length > 0
    ? allClosed.reduce((a, t) => a + (t.close_profit_abs ?? 0), 0) / allClosed.length : 0;
  const totalProfitDollar = allClosed.reduce((a, t) => a + (t.close_profit_abs ?? 0), 0);
  const avgPeakVal = s?.avg_left_on_table !== undefined && s?.avg_profit !== undefined
    ? (s.avg_profit + s.avg_left_on_table) : 0;
  const exitEfficiency = avgPeakVal > 0 ? 1 - ((s?.avg_left_on_table ?? 0) / avgPeakVal) : 0;
  return {
    pair: 'ALL PAIRS',
    trades: s?.total_trades ?? 0,
    open: s?.open_trades ?? 0,
    winRate,
    avgProfit: s?.avg_profit ?? 0,
    avgProfitDollar,
    totalProfitDollar,
    avgConfidence: avgConf,
    confToWinRate,
    confToProfitRatio: confToWinRate,
    exitEfficiency,
    avgPeak: 0,
    avgLeft: s?.avg_left_on_table ?? 0,
    avgDrawdown: s?.avg_drawdown_from_peak ?? 0,
    score: 0,
  };
});

watch(pairStats, (stats) => {
  if (stats.length < 2) { packTightnessScore.value = 100; return; }
  const sc = stats.map((s) => s.score);
  const mean = sc.reduce((a, b) => a + b, 0) / sc.length;
  const variance = sc.reduce((a, v) => a + (v - mean) ** 2, 0) / sc.length;
  const cv = mean > 0 ? Math.sqrt(variance) / mean : 0;
  packTightnessScore.value = Math.round(Math.max(0, Math.min(100, (1 - cv) * 100)));
});

function selectPair(pair: string | null) {
  selectedPair.value = pair;
  currentPage.value = 1;
}

// Pagination computed
const totalPages = computed(() => Math.ceil(allTrades.value.length / pageSize));
const paginatedTrades = computed(() => {
  const start = (currentPage.value - 1) * pageSize;
  // Open trades first, then closed sorted by close_date descending
  const openTrades = allTrades.value.filter((t) => t.is_open).sort((a, b) => {
    const da = a.open_date ? new Date(a.open_date).getTime() : 0;
    const db = b.open_date ? new Date(b.open_date).getTime() : 0;
    return db - da;
  });
  const closedTrades = allTrades.value.filter((t) => !t.is_open).sort((a, b) => {
    const da = a.close_date ? new Date(a.close_date).getTime() : 0;
    const db = b.close_date ? new Date(b.close_date).getTime() : 0;
    return db - da;
  });
  const sorted = [...openTrades, ...closedTrades];
  return sorted.slice(start, start + pageSize);
});

function goToPage(page: number) {
  if (page >= 1 && page <= totalPages.value) currentPage.value = page;
}

const confidenceVsProfitChart = computed<EChartsOption>(() => {
  const trades = chartClosedTrades.value;
  // Build confidence buckets for win rate line
  const buckets = Array.from({ length: 10 }, (_, i) => ({ min: i/10, max: (i+1)/10, wins: 0, total: 0 }));
  for (const t of trades) {
    const idx = Math.min(9, Math.floor(t.model_confidence * 10));
    buckets[idx].total++;
    if ((t.close_profit ?? 0) > 0) buckets[idx].wins++;
  }
  const bucketLabels = buckets.map((_, i) => (i * 10 + 5) / 100); // midpoints: 0.05, 0.15, ...
  const winRates = buckets.map((b) => b.total > 0 ? (b.wins / b.total) : null);

  return {
    title: { text: 'Confidence vs Profit & Win Rate', left: 'center', textStyle: { fontSize: 18 } },
    tooltip: { trigger: 'item', formatter: (p: any) => {
      if (p.seriesType === 'line') return `Conf ${(p.data[0]*100).toFixed(0)}%: Win Rate ${(p.data[1]*100).toFixed(0)}%`;
      const d = p.data; return `#${d[3]} ${d[4]}<br/>Confidence: ${(d[0]*100).toFixed(0)}%<br/>Profit: ${(d[1]*100).toFixed(2)}%<br/>Leverage: ${d[2]}x`;
    } },
    xAxis: { name: 'Model Confidence', nameLocation: 'middle', nameGap: 30, min: 0, max: 1 },
    yAxis: [
      { name: 'Close Profit %', nameLocation: 'middle', nameGap: 45, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
      { name: 'Win Rate %', nameLocation: 'middle', nameGap: 35, position: 'right', min: 0, max: 1, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(0)}%` }, splitLine: { show: false } },
    ],
    legend: { top: 30, data: ['Trades', 'Win Rate by Confidence'] },
    series: [
      { name: 'Trades', type: 'scatter', symbolSize: (d: number[]) => Math.max(6, Math.min(20, d[2]*3)),
        data: trades.map((t) => [t.model_confidence, t.close_profit ?? 0, t.leverage, t.id, t.pair]),
        itemStyle: { color: (p: any) => (p.data[1] >= 0 ? '#22c55e' : '#ef4444') },
        markLine: { data: [{ yAxis: 0, lineStyle: { color: '#666', type: 'dashed' } }], silent: true } },
      { name: 'Win Rate by Confidence', type: 'line', yAxisIndex: 1, smooth: true, lineStyle: { width: 3, color: '#3b82f6' }, symbol: 'circle', symbolSize: 8,
        itemStyle: { color: '#3b82f6' },
        data: bucketLabels.map((x, i) => winRates[i] !== null ? [x, winRates[i]] : null).filter(Boolean),
        // Add "perfect calibration" reference line
        markLine: { data: [[{ coord: [0, 0] }, { coord: [1, 1] }]], lineStyle: { color: '#ffffff30', type: 'dashed' }, label: { formatter: 'Perfect calibration', position: 'insideEndTop', fontSize: 11, color: '#ffffff80', distance: 10 }, silent: true } },
    ],
  };
});

const peakVsCloseChart = computed<EChartsOption>(() => {
  const trades = chartTrades.value.filter((t) => t.peak_profit !== null);
  // Calculate overall exit efficiency: 1 - (avgLeft / avgPeak)
  const closedWithPeak = trades.filter((t) => !t.is_open && t.peak_profit && t.peak_profit > 0);
  const chartAvgPeak = closedWithPeak.length > 0 ? closedWithPeak.reduce((s, t) => s + (t.peak_profit ?? 0), 0) / closedWithPeak.length : 0;
  const closedWithLeft = trades.filter((t) => !t.is_open && t.left_on_table !== null);
  const chartAvgLeft = closedWithLeft.length > 0 ? closedWithLeft.reduce((s, t) => s + (t.left_on_table ?? 0), 0) / closedWithLeft.length : 0;
  const efficiency = chartAvgPeak > 0 ? 1 - (chartAvgLeft / chartAvgPeak) : 0;
  const effStr = `${(efficiency * 100).toFixed(1)}%`;
  return {
    title: { text: `Exit Efficiency: ${effStr}  (1 − left/peak)`, left: 'center', textStyle: { fontSize: 18 }, subtextStyle: { fontSize: 14 } },
    tooltip: { trigger: 'item', formatter: (p: any) => {
      const d = p.data;
      const eff = d[0] > 0 ? ((d[1] / d[0]) * 100).toFixed(1) : 'N/A';
      return `#${d[3]} ${d[4]}<br/>Peak: ${(d[0]*100).toFixed(2)}%<br/>Close: ${(d[1]*100).toFixed(2)}%<br/>Left: ${((d[0]-d[1])*100).toFixed(2)}%<br/>Efficiency: ${eff}%`;
    } },
    xAxis: { name: 'Peak Profit %', nameLocation: 'middle', nameGap: 30, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
    yAxis: { name: 'Close Profit %', nameLocation: 'middle', nameGap: 45, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
    series: [{ type: 'scatter', symbolSize: 10,
      data: trades.map((t) => [t.peak_profit, t.close_profit ?? 0, t.left_on_table ?? 0, t.id, t.pair, t.is_open]),
      itemStyle: { color: (p: any) => (p.data[5] ? '#f59e0b' : p.data[1] >= 0 ? '#22c55e' : '#ef4444') },
      markLine: { data: [[{ coord: [0, 0] }, { coord: [0.15, 0.15] }]], lineStyle: { color: '#22c55e44', type: 'dashed', width: 2 }, label: { formatter: '100% efficiency', position: 'end', fontSize: 10 }, silent: true } }],
  };
});

const tradeJourneyChart = computed<EChartsOption>(() => {
  const trades = [...chartTrades.value.filter((t) => t.peak_profit !== null || t.trough_profit !== null)].reverse();
  const ids = trades.map((t) => `#${t.id}`);
  return {
    title: { text: 'Trade Journey: Peak / Close / Trough', left: 'center', textStyle: { fontSize: 18 } },
    tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' }, formatter: (params: any) => {
      const t = trades[params[0]?.dataIndex]; if (!t) return '';
      return `<b>#${t.id} ${t.pair}</b> (${t.enter_tag})<br/>Peak: ${((t.peak_profit??0)*100).toFixed(2)}%<br/>Close: ${((t.close_profit??0)*100).toFixed(2)}%<br/>Trough: ${((t.trough_profit??0)*100).toFixed(2)}%<br/>Exit: ${t.exit_tag||t.exit_reason||'open'}<br/>Conf: ${(t.model_confidence*100).toFixed(0)}%`;
    } },
    xAxis: { type: 'category', data: ids },
    yAxis: { name: 'Profit %', axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
    series: [
      { name: 'Peak', type: 'bar', data: trades.map((t) => t.peak_profit ?? 0), itemStyle: { color: '#22c55e88' }, barGap: '-100%' },
      { name: 'Close', type: 'bar', data: trades.map((t) => t.close_profit ?? 0), itemStyle: { color: (p: any) => { const t = trades[p.dataIndex]; return t?.is_open ? '#f59e0b' : (t?.close_profit??0) >= 0 ? '#22c55e' : '#ef4444'; } }, barGap: '-100%' },
      { name: 'Trough', type: 'bar', data: trades.map((t) => t.trough_profit ?? 0), itemStyle: { color: '#ef444466' }, barGap: '-100%' },
    ],
    legend: { top: 30 },
  };
});

const confidenceDistChart = computed<EChartsOption>(() => {
  const buckets = Array.from({ length: 10 }, (_, i) => ({ label: `${i*10}-${(i+1)*10}%`, min: i/10, max: (i+1)/10, wins: 0, losses: 0, total: 0 }));
  for (const t of chartTrades.value) { const idx = Math.min(9, Math.floor(t.model_confidence * 10)); buckets[idx].total++; if ((t.close_profit ?? 0) > 0) buckets[idx].wins++; else buckets[idx].losses++; }
  return {
    title: { text: 'Confidence Distribution & Win Rate', left: 'center', textStyle: { fontSize: 18 } },
    tooltip: { trigger: 'axis' },
    xAxis: { type: 'category', data: buckets.map((b) => b.label) },
    yAxis: [{ name: 'Count', type: 'value' }, { name: 'Win Rate %', type: 'value', max: 100, axisLabel: { formatter: '{value}%' } }],
    series: [
      { name: 'Wins', type: 'bar', stack: 'c', data: buckets.map((b) => b.wins), itemStyle: { color: '#22c55e' } },
      { name: 'Losses', type: 'bar', stack: 'c', data: buckets.map((b) => b.losses), itemStyle: { color: '#ef4444' } },
      { name: 'Win Rate', type: 'line', yAxisIndex: 1, data: buckets.map((b) => b.total > 0 ? Math.round((b.wins/b.total)*100) : 0), itemStyle: { color: '#3b82f6' } },
    ],
    legend: { top: 30 },
  };
});

function formatDuration(t: TradePerf): string {
  let mins = t.duration_mins;
  if (mins === null || mins === undefined) {
    // Open trade — calculate from open_date to now
    if (t.is_open && t.open_date) {
      const opened = new Date(t.open_date).getTime();
      const now = Date.now();
      mins = Math.floor((now - opened) / 60000);
    } else {
      return '—';
    }
  }
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  if (h < 24) return `${h}h ${m}m`;
  const d = Math.floor(h / 24);
  const rh = h % 24;
  return `${d}d ${rh}h`;
}

function phaseClass(phase: string | null): string {
  switch (phase) {
    case 'Entry':           return 'bg-red-900/50 text-red-400';        // dark red bg, bright red font — fresh trade
    case 'Loss_Mitigation': return 'bg-red-900/50 text-red-950';        // bright red bg, dark red font — RL cutting loser
    case 'Patience_S1':     return 'bg-red-600/30 text-red-400';        // medium red — first patience squeeze
    case 'Patience_S2':     return 'bg-red-500/25 text-red-400';        // lighter red — second patience squeeze
    case 'Trailing':        return 'bg-green-900/50 text-green-400';    // dark green bg, bright green font — winner trailing
    case 'Entry_SL':        return 'bg-red-900/50 text-red-400';        // legacy v10 compat
    case 'Stoploss':        return 'bg-red-500/20 text-red-400';        // legacy compat
    case 'Armed_SL':        return 'bg-yellow-500/25 text-yellow-300';  // legacy compat
    case 'RL_Exit':       return 'bg-cyan-500/25 text-cyan-300';      // cyan — model timed exit
    default:              return 'text-surface-500';
  }
}

function pct(v: number | null | undefined, d = 2): string { if (v === null || v === undefined) return '—'; return `${(v*100).toFixed(d)}%`; }
</script>

<template>
  <div class="p-4 h-full overflow-y-auto">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-3xl font-bold">Model Performance</h1>
      <Button size="small" @click="fetchPerformance" :loading="loading"><i-mdi-refresh class="mr-1" /> Refresh</Button>
    </div>
    <div v-if="error" class="bg-red-500/20 text-red-400 p-3 rounded mb-4">{{ error }}</div>
    <div v-if="loading && !perfData" class="flex justify-center py-20"><ProgressSpinner class="w-8 h-8" /></div>
    <template v-if="perfData">
      <!-- ═══ TOP: Pair Stats Breakdown Table ═══ -->
      <div class="bg-surface-800 rounded-lg p-4 mb-6">
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-3">
            <h2 class="text-xl font-semibold">Pair Breakdown</h2>
            <span v-if="selectedPair" class="text-base text-primary-400 cursor-pointer" @click="selectPair(null)">← Show All Pairs</span>
          </div>
          <div class="flex items-center gap-1">
            <span class="text-base text-surface-400 mr-2">Show:</span>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="tableTradeLimit === null ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setTableLimit(null)"
            >All</button>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="tableTradeLimit === 100 ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setTableLimit(100)"
            >Last 100</button>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="tableTradeLimit === 50 ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setTableLimit(50)"
            >Last 50</button>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="tableTradeLimit === 10 ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setTableLimit(10)"
            >Last 10</button>
          </div>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full" style="font-size: 1.125rem;">
            <thead><tr class="border-b-2 border-surface-500" style="font-size: 1.06rem;">
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Pair</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Trades</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Open</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Win Rate</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Avg Conf</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide" title="Win Rate / Avg Confidence — 1.0 = perfectly calibrated">Conf→Win</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Avg Profit</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide" title="Average profit per trade in dollars">Avg $</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide" title="Total profit from all closed trades">Total $</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide" title="Close profit / Peak profit — 100% = perfect exit, 0% = gave it all back, negative = lost more than peak">Exit Eff</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Avg Peak</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Avg Left</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Avg DD</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide" title="Efficiency score — comparable across rigs with different coin counts">Score</th>
            </tr></thead>
            <tbody>
              <tr
                v-for="ps in [...pairStats].sort((a, b) => b.score - a.score)" :key="ps.pair"
                class="border-b border-surface-700 cursor-pointer transition-colors"
                :class="selectedPair === ps.pair ? 'bg-primary-500/15 border-primary-500/30' : 'hover:bg-surface-700/50'"
                @click="selectPair(ps.pair)"
              >
                <td class="p-2.5 text-center font-semibold">{{ ps.pair }}</td>
                <td class="p-2.5 text-center font-mono">{{ ps.trades }}</td>
                <td class="p-2.5 text-center font-mono" :class="ps.open > 0 ? 'text-cyan-400' : ''">{{ ps.open }}</td>
                <td class="p-2.5 text-center font-mono" :class="ps.winRate >= 0.5 ? 'text-green-400' : 'text-red-400'">{{ pct(ps.winRate, 1) }}</td>
                <td class="p-2.5 text-center font-mono text-blue-400">{{ pct(ps.avgConfidence, 0) }}</td>
                <td class="p-2.5 text-center font-mono" :class="ps.confToWinRate >= 0.9 ? 'text-green-400' : ps.confToWinRate >= 0.7 ? 'text-yellow-400' : 'text-red-400'">{{ ps.confToWinRate.toFixed(2) }}x</td>
                <td class="p-2.5 text-center font-mono" :class="ps.avgProfit >= 0 ? 'text-green-400' : 'text-red-400'">{{ pct(ps.avgProfit) }}</td>
                <td class="p-2.5 text-center font-mono" :class="ps.avgProfitDollar >= 0 ? 'text-green-400' : 'text-red-400'">${{ ps.avgProfitDollar.toFixed(2) }}</td>
                <td class="p-2.5 text-center font-mono font-semibold" :class="ps.totalProfitDollar >= 0 ? 'text-green-400' : 'text-red-400'">${{ ps.totalProfitDollar.toFixed(2) }}</td>
                <td class="p-2.5 text-center font-mono" :class="ps.exitEfficiency >= 0.7 ? 'text-green-400' : ps.exitEfficiency >= 0 ? 'text-yellow-400' : 'text-red-400'">{{ pct(ps.exitEfficiency, 1) }}</td>
                <td class="p-2.5 text-center font-mono" :class="ps.avgPeak >= 0 ? 'text-green-400' : 'text-red-400'">{{ pct(ps.avgPeak) }}</td>
                <td class="p-2.5 text-center font-mono text-yellow-400">{{ pct(ps.avgLeft) }}</td>
                <td class="p-2.5 text-center font-mono text-red-400">{{ pct(ps.avgDrawdown) }}</td>
                <td class="p-2.5 text-center font-mono font-bold" :class="ps.score >= pairStats[0]?.score * 0.8 ? 'text-green-400' : ps.score >= pairStats[0]?.score * 0.5 ? 'text-yellow-400' : 'text-red-400'">{{ ps.score }} ({{ Math.round(ps.score / (pairStats.length * 10) * 100) }}%)</td>
              </tr>
              <!-- ALL PAIRS summary row -->
              <tr
                class="border-t-2 border-surface-500 cursor-pointer font-bold transition-colors"
                :class="selectedPair === null ? 'bg-primary-500/15 border-primary-500/30' : 'hover:bg-surface-700/50'"
                @click="selectPair(null)"
              >
                <td class="p-2.5 text-center uppercase text-primary-400">All Pairs</td>
                <td class="p-2.5 text-center font-mono">{{ allPairsSummary.trades }}</td>
                <td class="p-2.5 text-center font-mono" :class="allPairsSummary.open > 0 ? 'text-cyan-400' : ''">{{ allPairsSummary.open }}</td>
                <td class="p-2.5 text-center font-mono" :class="allPairsSummary.winRate >= 0.5 ? 'text-green-400' : 'text-red-400'">{{ pct(allPairsSummary.winRate, 1) }}</td>
                <td class="p-2.5 text-center font-mono text-blue-400">{{ pct(allPairsSummary.avgConfidence, 0) }}</td>
                <td class="p-2.5 text-center font-mono" :class="allPairsSummary.confToWinRate >= 0.9 ? 'text-green-400' : allPairsSummary.confToWinRate >= 0.7 ? 'text-yellow-400' : 'text-red-400'">{{ allPairsSummary.confToWinRate.toFixed(2) }}x</td>
                <td class="p-2.5 text-center font-mono" :class="allPairsSummary.avgProfit >= 0 ? 'text-green-400' : 'text-red-400'">{{ pct(allPairsSummary.avgProfit) }}</td>
                <td class="p-2.5 text-center font-mono" :class="allPairsSummary.avgProfitDollar >= 0 ? 'text-green-400' : 'text-red-400'">${{ allPairsSummary.avgProfitDollar.toFixed(2) }}</td>
                <td class="p-2.5 text-center font-mono font-semibold" :class="allPairsSummary.totalProfitDollar >= 0 ? 'text-green-400' : 'text-red-400'">${{ allPairsSummary.totalProfitDollar.toFixed(2) }}</td>
                <td class="p-2.5 text-center font-mono" :class="allPairsSummary.exitEfficiency >= 0.7 ? 'text-green-400' : allPairsSummary.exitEfficiency >= 0 ? 'text-yellow-400' : 'text-red-400'">{{ pct(allPairsSummary.exitEfficiency, 1) }}</td>
                <td class="p-2.5 text-center font-mono text-green-400">—</td>
                <td class="p-2.5 text-center font-mono text-yellow-400">{{ pct(allPairsSummary.avgLeft) }}</td>
                <td class="p-2.5 text-center font-mono text-red-400">{{ pct(allPairsSummary.avgDrawdown) }}</td>
                <td class="p-2.5 text-center font-mono font-bold" :class="packTightnessScore >= 75 ? 'text-green-400' : packTightnessScore >= 50 ? 'text-yellow-400' : 'text-red-400'">{{ packTightnessScore }}%</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- ═══ MIDDLE: Charts ═══ -->
      <div class="mb-6">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-xl font-semibold">Charts</h2>
          <div class="flex items-center gap-1">
            <span class="text-base text-surface-400 mr-2">Show:</span>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="chartTradeLimit === null ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setChartLimit(null)"
            >All</button>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="chartTradeLimit === 100 ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setChartLimit(100)"
            >Last 100</button>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="chartTradeLimit === 50 ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setChartLimit(50)"
            >Last 50</button>
            <button
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="chartTradeLimit === 10 ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="setChartLimit(10)"
            >Last 10</button>
          </div>
        </div>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div class="bg-surface-800 rounded-lg p-3 h-96"><ECharts :option="confidenceVsProfitChart" :theme="theme" autoresize class="w-full h-full" /></div>
          <div class="bg-surface-800 rounded-lg p-3 h-96"><ECharts :option="peakVsCloseChart" :theme="theme" autoresize class="w-full h-full" /></div>
          <div class="bg-surface-800 rounded-lg p-3 h-96"><ECharts :option="tradeJourneyChart" :theme="theme" autoresize class="w-full h-full" /></div>
          <div class="bg-surface-800 rounded-lg p-3 h-96"><ECharts :option="confidenceDistChart" :theme="theme" autoresize class="w-full h-full" /></div>
        </div>
      </div>

      <!-- Trade Details Table — Paginated, larger font -->
      <div class="bg-surface-800 rounded-lg p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-xl font-semibold">Trade Details</h2>
          <div class="flex items-center gap-2 text-base">
            <span class="text-surface-400">{{ allTrades.length }} trades</span>
            <span class="text-surface-500">|</span>
            <span class="text-surface-400">Page {{ currentPage }} of {{ totalPages }}</span>
          </div>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full" style="font-size: 1.16rem;">
            <thead><tr class="border-b-2 border-surface-500" style="font-size: 1.1rem;">
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">#</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Pair</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Dir</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Conf</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Lev</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Stake</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Profit</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Peak</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Trough</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Left</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Phase</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Exit</th>
              <th class="text-center p-2.5 uppercase font-bold text-white tracking-wide">Duration</th>
            </tr></thead>
            <tbody>
              <tr v-for="t in paginatedTrades" :key="t.id" class="border-b border-surface-700 hover:bg-surface-700/50" :class="{ 'opacity-70': t.is_open }">
                <td class="p-2.5 text-center">{{ t.id }}</td>
                <td class="p-2.5 text-center font-mono">{{ t.pair }}</td>
                <td class="p-2.5 text-center"><span :class="t.direction === 'long' ? 'text-green-400' : 'text-red-400'">{{ t.direction.toUpperCase() }}</span></td>
                <td class="p-2.5 text-center font-mono">{{ (t.model_confidence*100).toFixed(0) }}%</td>
                <td class="p-2.5 text-center">{{ t.leverage }}x</td>
                <td class="p-2.5 text-center font-mono">${{ t.stake_amount.toFixed(1) }}</td>
                <td class="p-2.5 text-center font-mono" :class="(t.close_profit??0) >= 0 ? 'text-green-400' : 'text-red-400'">{{ t.close_profit !== null ? pct(t.close_profit) : '—' }}<span v-if="t.is_open" class="text-xs text-cyan-400 ml-1">●</span></td>
                <td class="p-2.5 text-center font-mono text-green-400">{{ pct(t.peak_profit) }}</td>
                <td class="p-2.5 text-center font-mono text-red-400">{{ pct(t.trough_profit) }}</td>
                <td class="p-2.5 text-center font-mono text-yellow-400">{{ pct(t.left_on_table) }}</td>
                <td class="p-2.5 text-center"><span class="px-1.5 py-0.5 rounded font-semibold" :class="phaseClass(t.sl_phase)">{{ t.sl_phase || '—' }}</span></td>
                <td class="p-2.5 text-center max-w-48 truncate" :title="t.exit_tag || t.exit_reason || ''">{{ t.exit_tag || t.exit_reason || (t.is_open ? '—' : 'unknown') }}</td>
                <td class="p-2.5 text-center">{{ formatDuration(t) }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Pagination controls -->
        <div v-if="totalPages > 1" class="flex items-center justify-center gap-2 mt-4 pt-3 border-t border-surface-700">
          <button
            class="px-3 py-1.5 rounded text-base font-semibold transition-colors"
            :class="currentPage === 1 ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === 1"
            @click="goToPage(1)"
          >« First</button>
          <button
            class="px-3 py-1.5 rounded text-base font-semibold transition-colors"
            :class="currentPage === 1 ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === 1"
            @click="goToPage(currentPage - 1)"
          >‹ Prev</button>

          <template v-for="p in totalPages" :key="p">
            <button
              v-if="p === 1 || p === totalPages || (p >= currentPage - 2 && p <= currentPage + 2)"
              class="px-3 py-1.5 rounded text-base font-semibold transition-colors cursor-pointer"
              :class="p === currentPage ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="goToPage(p)"
            >{{ p }}</button>
            <span
              v-else-if="p === currentPage - 3 || p === currentPage + 3"
              class="text-surface-600 px-1"
            >…</span>
          </template>

          <button
            class="px-3 py-1.5 rounded text-base font-semibold transition-colors"
            :class="currentPage === totalPages ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === totalPages"
            @click="goToPage(currentPage + 1)"
          >Next ›</button>
          <button
            class="px-3 py-1.5 rounded text-base font-semibold transition-colors"
            :class="currentPage === totalPages ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === totalPages"
            @click="goToPage(totalPages)"
          >Last »</button>
        </div>
      </div>
    </template>
  </div>
</template>
VUEEOF
echo "    Done."

# ── FRONTEND: Router (using Python for safe insertion) ──
echo "  [02] Patching router..."
if grep -q "PerformanceView" "$ROUTER_FILE"; then
    echo "    Already patched, skipping."
else
    python3 -c "
with open('$ROUTER_FILE', 'r') as f:
    content = f.read()
insert = '''  {
    path: '/performance',
    name: 'Model Performance',
    component: () => import('@/views/PerformanceView.vue'),
  },
'''
content = content.replace(
    \"\"\"  {
    path: '/settings',\"\"\",
    insert + \"\"\"  {
    path: '/settings',\"\"\"
)
with open('$ROUTER_FILE', 'w') as f:
    f.write(content)
"
    echo "    Done."
fi

# ── FRONTEND: NavBar (using Python for safe insertion) ──
echo "  [02] Patching NavBar..."
if grep -q "performance" "$NAVBAR_FILE"; then
    echo "    Already patched, skipping."
else
    python3 -c "
with open('$NAVBAR_FILE', 'r') as f:
    content = f.read()
insert = '''  {
    label: 'Performance',
    to: '/performance',
    visible: computed(() => !botStore.canRunBacktest),
    icon: 'i-mdi-chart-box-outline',
  },
'''
content = content.replace(
    \"\"\"  {
    label: 'Chart',\"\"\",
    insert + \"\"\"  {
    label: 'Chart',\"\"\"
)
with open('$NAVBAR_FILE', 'w') as f:
    f.write(content)
"
    echo "    Done."
fi

echo "  [02] Performance dashboard patch complete."
