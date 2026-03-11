#!/usr/bin/env bash
# ============================================================
# Patch 02: Performance Dashboard
#
# BACKEND:  Adds /performance/model endpoint (bulk DB query, no N+1)
# FRONTEND: PerformanceView.vue + router + navbar entry
#           - Paginated table (50 trades per page)
#           - 30% larger table font
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
            open_rate = float(t.open_rate) if t.open_rate else 0
            close_rate = float(t.close_rate) if t.close_rate else None
            max_rate = float(t.max_rate) if t.max_rate else None
            min_rate = float(t.min_rate) if t.min_rate else None

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
if grep -q "performance_model" "$API_FILE"; then
    echo "    Already patched, skipping."
else
    sed -i '/@router.get("\/pair_candles", response_model=PairHistory/i\
@router.get("/performance/model", tags=["Performance"])\
def performance_model(rpc: RPC = Depends(get_rpc)):\
    return rpc._rpc_model_performance()\
\
' "$API_FILE"
    echo "    Done."
fi

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
  close_profit: number | null; max_rate: number | null; min_rate: number | null;
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

// Pagination state
const currentPage = ref(1);
const pageSize = 50;

async function fetchPerformance() {
  loading.value = true; error.value = '';
  try {
    const { api } = botStore.activeBot;
    const { data } = await api.get<PerfResponse>('/performance/model');
    perfData.value = data;
    currentPage.value = 1; // Reset to first page on refresh
  } catch (e: any) {
    error.value = e?.message || 'Failed to load';
  } finally { loading.value = false; }
}

onMounted(() => fetchPerformance());

const theme = computed(() => settingsStore.chartTheme);
const closedTrades = computed(() => perfData.value?.trades.filter((t) => !t.is_open) ?? []);
const allTrades = computed(() => perfData.value?.trades ?? []);

// Pagination computed
const totalPages = computed(() => Math.ceil(allTrades.value.length / pageSize));
const paginatedTrades = computed(() => {
  const start = (currentPage.value - 1) * pageSize;
  // Show most recent trades first (reverse order)
  const sorted = [...allTrades.value].reverse();
  return sorted.slice(start, start + pageSize);
});

function goToPage(page: number) {
  if (page >= 1 && page <= totalPages.value) currentPage.value = page;
}

const confidenceVsProfitChart = computed<EChartsOption>(() => {
  const trades = closedTrades.value;
  return {
    title: { text: 'Model Confidence vs Trade Profit', left: 'center', textStyle: { fontSize: 14 } },
    tooltip: { trigger: 'item', formatter: (p: any) => { const d = p.data; return `#${d[3]} ${d[4]}<br/>Confidence: ${(d[0]*100).toFixed(0)}%<br/>Profit: ${(d[1]*100).toFixed(2)}%<br/>Leverage: ${d[2]}x`; } },
    xAxis: { name: 'Model Confidence', nameLocation: 'middle', nameGap: 30, min: 0, max: 1 },
    yAxis: { name: 'Close Profit %', nameLocation: 'middle', nameGap: 45, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
    series: [{ type: 'scatter', symbolSize: (d: number[]) => Math.max(6, Math.min(20, d[2]*3)),
      data: trades.map((t) => [t.model_confidence, t.close_profit ?? 0, t.leverage, t.id, t.pair]),
      itemStyle: { color: (p: any) => (p.data[1] >= 0 ? '#22c55e' : '#ef4444') },
      markLine: { data: [{ yAxis: 0, lineStyle: { color: '#666', type: 'dashed' } }], silent: true } }],
  };
});

const peakVsCloseChart = computed<EChartsOption>(() => {
  const trades = allTrades.value.filter((t) => t.peak_profit !== null);
  return {
    title: { text: 'Peak Profit vs Close Profit', left: 'center', textStyle: { fontSize: 14 } },
    tooltip: { trigger: 'item', formatter: (p: any) => { const d = p.data; return `#${d[3]} ${d[4]}<br/>Peak: ${(d[0]*100).toFixed(2)}%<br/>Close: ${(d[1]*100).toFixed(2)}%<br/>Left: ${((d[0]-d[1])*100).toFixed(2)}%`; } },
    xAxis: { name: 'Peak Profit %', nameLocation: 'middle', nameGap: 30, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
    yAxis: { name: 'Close Profit %', nameLocation: 'middle', nameGap: 45, axisLabel: { formatter: (v: number) => `${(v*100).toFixed(1)}%` } },
    series: [{ type: 'scatter', symbolSize: 10,
      data: trades.map((t) => [t.peak_profit, t.close_profit ?? 0, t.left_on_table ?? 0, t.id, t.pair, t.is_open]),
      itemStyle: { color: (p: any) => (p.data[5] ? '#f59e0b' : p.data[1] >= 0 ? '#22c55e' : '#ef4444') },
      markLine: { data: [[{ coord: [0, 0] }, { coord: [0.15, 0.15] }]], lineStyle: { color: '#666', type: 'dashed' }, label: { formatter: 'Perfect exit', position: 'end' }, silent: true } }],
  };
});

const tradeJourneyChart = computed<EChartsOption>(() => {
  const trades = allTrades.value.filter((t) => t.peak_profit !== null || t.trough_profit !== null);
  const ids = trades.map((t) => `#${t.id}`);
  return {
    title: { text: 'Trade Journey: Peak / Close / Trough', left: 'center', textStyle: { fontSize: 14 } },
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
  for (const t of allTrades.value) { const idx = Math.min(9, Math.floor(t.model_confidence * 10)); buckets[idx].total++; if ((t.close_profit ?? 0) > 0) buckets[idx].wins++; else buckets[idx].losses++; }
  return {
    title: { text: 'Confidence Distribution & Win Rate', left: 'center', textStyle: { fontSize: 14 } },
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

function pct(v: number | null | undefined, d = 2): string { if (v === null || v === undefined) return '—'; return `${(v*100).toFixed(d)}%`; }
</script>

<template>
  <div class="p-4 h-full overflow-y-auto">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-2xl font-bold">Model Performance</h1>
      <Button size="small" @click="fetchPerformance" :loading="loading"><i-mdi-refresh class="mr-1" /> Refresh</Button>
    </div>
    <div v-if="error" class="bg-red-500/20 text-red-400 p-3 rounded mb-4">{{ error }}</div>
    <div v-if="loading && !perfData" class="flex justify-center py-20"><ProgressSpinner class="w-8 h-8" /></div>
    <template v-if="perfData">
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <div class="bg-surface-800 rounded-lg p-3 text-center"><div class="text-sm text-surface-400">Total Trades</div><div class="text-2xl font-bold">{{ perfData.summary.total_trades }}</div><div class="text-xs text-surface-500">{{ perfData.summary.open_trades }} open</div></div>
        <div class="bg-surface-800 rounded-lg p-3 text-center"><div class="text-sm text-surface-400">Win Rate</div><div class="text-2xl font-bold" :class="perfData.summary.win_rate >= 0.5 ? 'text-green-400' : 'text-red-400'">{{ pct(perfData.summary.win_rate, 1) }}</div></div>
        <div class="bg-surface-800 rounded-lg p-3 text-center"><div class="text-sm text-surface-400">Avg Confidence</div><div class="text-2xl font-bold text-blue-400">{{ pct(perfData.summary.avg_model_confidence, 0) }}</div></div>
        <div class="bg-surface-800 rounded-lg p-3 text-center"><div class="text-sm text-surface-400">Avg Profit</div><div class="text-2xl font-bold" :class="perfData.summary.avg_profit >= 0 ? 'text-green-400' : 'text-red-400'">{{ pct(perfData.summary.avg_profit) }}</div></div>
        <div class="bg-surface-800 rounded-lg p-3 text-center"><div class="text-sm text-surface-400">Avg Left on Table</div><div class="text-2xl font-bold text-yellow-400">{{ pct(perfData.summary.avg_left_on_table) }}</div><div class="text-xs text-surface-500">peak - close</div></div>
        <div class="bg-surface-800 rounded-lg p-3 text-center"><div class="text-sm text-surface-400">Avg Peak→Trough</div><div class="text-2xl font-bold text-red-400">{{ pct(perfData.summary.avg_drawdown_from_peak) }}</div><div class="text-xs text-surface-500">max drawdown from peak</div></div>
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
        <div class="bg-surface-800 rounded-lg p-3 h-80"><ECharts :option="confidenceVsProfitChart" :theme="theme" autoresize class="w-full h-full" /></div>
        <div class="bg-surface-800 rounded-lg p-3 h-80"><ECharts :option="peakVsCloseChart" :theme="theme" autoresize class="w-full h-full" /></div>
        <div class="bg-surface-800 rounded-lg p-3 h-80"><ECharts :option="tradeJourneyChart" :theme="theme" autoresize class="w-full h-full" /></div>
        <div class="bg-surface-800 rounded-lg p-3 h-80"><ECharts :option="confidenceDistChart" :theme="theme" autoresize class="w-full h-full" /></div>
      </div>

      <!-- Trade Details Table — Paginated, larger font -->
      <div class="bg-surface-800 rounded-lg p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-lg font-semibold">Trade Details</h2>
          <div class="flex items-center gap-2 text-sm">
            <span class="text-surface-400">{{ allTrades.length }} trades</span>
            <span class="text-surface-500">|</span>
            <span class="text-surface-400">Page {{ currentPage }} of {{ totalPages }}</span>
          </div>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full" style="font-size: 0.93rem;">
            <thead><tr class="text-surface-400 border-b border-surface-600" style="font-size: 0.82rem;">
              <th class="text-left p-2.5">#</th><th class="text-left p-2.5">Pair</th><th class="text-left p-2.5">Dir</th>
              <th class="text-right p-2.5">Conf</th><th class="text-right p-2.5">Lev</th><th class="text-right p-2.5">Profit</th>
              <th class="text-right p-2.5">Peak</th><th class="text-right p-2.5">Trough</th><th class="text-right p-2.5">Left</th>
              <th class="text-left p-2.5">Phase</th><th class="text-left p-2.5">Exit</th><th class="text-right p-2.5">Duration</th>
            </tr></thead>
            <tbody>
              <tr v-for="t in paginatedTrades" :key="t.id" class="border-b border-surface-700 hover:bg-surface-700/50" :class="{ 'opacity-70': t.is_open }">
                <td class="p-2.5">{{ t.id }}</td>
                <td class="p-2.5 font-mono">{{ t.pair }}</td>
                <td class="p-2.5"><span :class="t.direction === 'long' ? 'text-green-400' : 'text-red-400'">{{ t.direction.toUpperCase() }}</span></td>
                <td class="p-2.5 text-right font-mono">{{ (t.model_confidence*100).toFixed(0) }}%</td>
                <td class="p-2.5 text-right">{{ t.leverage }}x</td>
                <td class="p-2.5 text-right font-mono" :class="(t.close_profit??0) >= 0 ? 'text-green-400' : 'text-red-400'">{{ t.is_open ? 'open' : pct(t.close_profit) }}</td>
                <td class="p-2.5 text-right font-mono text-green-400">{{ pct(t.peak_profit) }}</td>
                <td class="p-2.5 text-right font-mono text-red-400">{{ pct(t.trough_profit) }}</td>
                <td class="p-2.5 text-right font-mono text-yellow-400">{{ pct(t.left_on_table) }}</td>
                <td class="p-2.5"><span class="text-sm px-1.5 py-0.5 rounded" :class="{ 'bg-green-500/20 text-green-400': t.sl_phase === 'Trailing', 'bg-yellow-500/20 text-yellow-400': t.sl_phase === 'Armed_SL', 'bg-red-500/20 text-red-400': t.sl_phase === 'Stoploss' }">{{ t.sl_phase || '—' }}</span></td>
                <td class="p-2.5 max-w-48 truncate" :title="t.exit_tag || t.exit_reason || ''">{{ t.exit_tag || t.exit_reason || (t.is_open ? '—' : 'unknown') }}</td>
                <td class="p-2.5 text-right">{{ t.duration_mins ? `${Math.floor(t.duration_mins/60)}h ${t.duration_mins%60}m` : '—' }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Pagination controls -->
        <div v-if="totalPages > 1" class="flex items-center justify-center gap-2 mt-4 pt-3 border-t border-surface-700">
          <button
            class="px-3 py-1.5 rounded text-sm font-semibold transition-colors"
            :class="currentPage === 1 ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === 1"
            @click="goToPage(1)"
          >« First</button>
          <button
            class="px-3 py-1.5 rounded text-sm font-semibold transition-colors"
            :class="currentPage === 1 ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === 1"
            @click="goToPage(currentPage - 1)"
          >‹ Prev</button>

          <template v-for="p in totalPages" :key="p">
            <button
              v-if="p === 1 || p === totalPages || (p >= currentPage - 2 && p <= currentPage + 2)"
              class="px-3 py-1.5 rounded text-sm font-semibold transition-colors cursor-pointer"
              :class="p === currentPage ? 'bg-primary-500/30 text-primary-400 border border-primary-500/50' : 'text-surface-300 hover:bg-surface-700'"
              @click="goToPage(p)"
            >{{ p }}</button>
            <span
              v-else-if="p === currentPage - 3 || p === currentPage + 3"
              class="text-surface-600 px-1"
            >…</span>
          </template>

          <button
            class="px-3 py-1.5 rounded text-sm font-semibold transition-colors"
            :class="currentPage === totalPages ? 'text-surface-600 cursor-not-allowed' : 'text-surface-300 hover:bg-surface-700 cursor-pointer'"
            :disabled="currentPage === totalPages"
            @click="goToPage(currentPage + 1)"
          >Next ›</button>
          <button
            class="px-3 py-1.5 rounded text-sm font-semibold transition-colors"
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
    label: 'Logs',\"\"\",
    insert + \"\"\"  {
    label: 'Logs',\"\"\"
)
with open('$NAVBAR_FILE', 'w') as f:
    f.write(content)
"
    echo "    Done."
fi

echo "  [02] Performance dashboard patch complete."