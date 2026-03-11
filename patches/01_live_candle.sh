#!/usr/bin/env bash
# ============================================================
# Patch 01: Live Candle on Chart
#
# BACKEND:  Adds /pair_candles/live endpoint (reads in-memory cache)
# FRONTEND: Updates SingleCandleChartContainer to poll every 5s
#           and replace last candle OHLCV with fresh data.
# STORE:    Exposes api from ftbot store for component access.
#
# All backend insertions use Python to avoid sed escaping issues.
# ============================================================
set -euo pipefail

RPC_FILE="$FT_PACKAGE_DIR/rpc/rpc.py"
API_FILE="$FT_PACKAGE_DIR/rpc/api_server/api_trading.py"
STORE_FILE="$CS_UI_DIR/src/stores/ftbot.ts"
CONTAINER_FILE="$CS_UI_DIR/src/components/charts/SingleCandleChartContainer.vue"

# ── BACKEND: Add _rpc_live_candle to rpc.py ──
echo "  [01] Patching rpc.py..."
if grep -q "_rpc_live_candle" "$RPC_FILE"; then
    echo "    Already patched, skipping."
else
    python3 - "$RPC_FILE" << 'PYEOF'
import sys

filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

method = '''
    def _rpc_live_candle(self, pair: str, timeframe: str) -> dict[str, Any]:
        """Return the current incomplete candle from the exchange cache.
        Zero exchange API calls - reads from in-memory klines cache only.
        """
        from freqtrade.exchange import timeframe_to_msecs

        df = self._freqtrade.dataprovider.ohlcv(pair, timeframe)
        if df.empty:
            return {"pair": pair, "timeframe": timeframe, "candle": None}

        last_row = df.iloc[-1]
        return {
            "pair": pair,
            "timeframe": timeframe,
            "timeframe_ms": timeframe_to_msecs(timeframe),
            "candle": {
                "date": int(last_row["date"].timestamp() * 1000),
                "open": float(last_row["open"]),
                "high": float(last_row["high"]),
                "low": float(last_row["low"]),
                "close": float(last_row["close"]),
                "volume": float(last_row["volume"]),
            },
        }
'''

anchor = "    def _ws_all_analysed_dataframes"
if anchor in content:
    content = content.replace(anchor, method + "\n" + anchor)
    with open(filepath, "w") as f:
        f.write(content)
    print("    Done.")
else:
    print("    ERROR: anchor not found in rpc.py")
PYEOF
fi

# ── BACKEND: Add /pair_candles/live route ──
echo "  [01] Patching api_trading.py..."
python3 - "$API_FILE" << 'PYEOF'
import sys

filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

if "def pair_candles_live" in content:
    print("    Already patched, skipping.")
else:
    route = '''@router.get("/pair_candles/live", tags=["Candle data"])
def pair_candles_live(pair: str, timeframe: str, rpc: RPC = Depends(get_rpc)):
    return rpc._rpc_live_candle(pair, timeframe)


'''
    anchor = '@router.get("/pair_candles", response_model=PairHistory'
    if anchor in content:
        content = content.replace(anchor, route + anchor, 1)
        with open(filepath, "w") as f:
            f.write(content)
        print("    Done.")
    else:
        print("    ERROR: anchor not found in api_trading.py")
PYEOF

# ── STORE: Expose api from ftbot store ──
echo "  [01] Exposing api in ftbot store..."
python3 - "$STORE_FILE" << 'PYEOF'
import sys, re

filepath = sys.argv[1]
with open(filepath, "r") as f:
    content = f.read()

# Check if api is already in the return block
m = re.search(r'return \{([^}]{0,300})', content)
if m and 'api,' in m.group(1):
    print("    Already exposed, skipping.")
else:
    content = content.replace("return {", "return {\n        api,", 1)
    with open(filepath, "w") as f:
        f.write(content)
    print("    Done.")
PYEOF

# ── FRONTEND: Replace SingleCandleChartContainer.vue ──
echo "  [01] Updating SingleCandleChartContainer.vue..."
cat > "$CONTAINER_FILE" << 'VUEEOF'
<script setup lang="ts">
import type { ChartSliderPosition, PairHistory, Trade } from '@/types';
import { LoadingStatus } from '@/types';

const props = withDefaults(
  defineProps<{
    trades?: Trade[];
    availablePairs: string[];
    timeframe: string;
    historicView?: boolean;
    pair?: string;
    sliderPosition?: ChartSliderPosition;
    isSinglePairView?: boolean;
  }>(),
  {
    trades: () => [],
    historicView: false,
    pair: '',
    sliderPosition: undefined,
    isSinglePairView: true,
  },
);

const emit = defineEmits<{
  refreshData: [pair: string, columns: string[]];
}>();

const settingsStore = useSettingsStore();
const colorStore = useColorStore();
const botStore = useBotStore();
const plotStore = usePlotConfigStore();

// ── Live candle state ──
const liveCandle = ref<{
  date: number; open: number; high: number;
  low: number; close: number; volume: number;
} | null>(null);
let liveCandleTimer: ReturnType<typeof setInterval> | null = null;

async function fetchLiveCandle() {
  if (!props.pair || !props.timeframe || props.historicView) return;
  try {
    const { api } = botStore.activeBot;
    const { data } = await api.get('/pair_candles/live', {
      params: { pair: props.pair, timeframe: props.timeframe },
    });
    if (data && data.candle) {
      liveCandle.value = data.candle;
    }
  } catch (e) {
    console.debug('Live candle fetch failed:', e);
  }
}

function startLiveCandlePolling() {
  stopLiveCandlePolling();
  if (props.historicView) return;
  fetchLiveCandle();
  liveCandleTimer = setInterval(fetchLiveCandle, 5000);
}

function stopLiveCandlePolling() {
  if (liveCandleTimer) {
    clearInterval(liveCandleTimer);
    liveCandleTimer = null;
  }
  liveCandle.value = null;
}

// ── Dataset logic ──
const dataset = computed((): PairHistory => {
  if (props.historicView) {
    return botStore.activeBot.history[`${props.pair}__${props.timeframe}`]?.data;
  }
  return botStore.activeBot.candleData[`${props.pair}__${props.timeframe}`]?.data;
});

// Merge live candle into dataset
const datasetWithLiveCandle = computed((): PairHistory | undefined => {
  if (!dataset.value || !liveCandle.value) return dataset.value;

  const ds = dataset.value;
  const lc = liveCandle.value;
  const colDate = ds.columns.indexOf('__date_ts');
  const colOpen = ds.columns.indexOf('open');
  const colHigh = ds.columns.indexOf('high');
  const colLow = ds.columns.indexOf('low');
  const colClose = ds.columns.indexOf('close');
  const colVolume = ds.columns.indexOf('volume');

  if (colDate < 0 || colOpen < 0) return ds;

  const lastRow = ds.data[ds.data.length - 1];
  if (!lastRow) return ds;

  const lastClosedTs = lastRow[colDate];
  const liveCandleTs = lc.date;

  const newRow = new Array(ds.columns.length).fill(null);
  newRow[colDate] = liveCandleTs;
  newRow[colOpen] = lc.open;
  newRow[colHigh] = lc.high;
  newRow[colLow] = lc.low;
  newRow[colClose] = lc.close;
  newRow[colVolume] = lc.volume;

  const updatedData = [...ds.data];

  if (liveCandleTs === lastClosedTs) {
    updatedData[updatedData.length - 1] = newRow;
  } else if (liveCandleTs > lastClosedTs) {
    updatedData.push(newRow);
  } else {
    return ds;
  }

  return { ...ds, data: updatedData, length: updatedData.length };
});

const datasetColumns = computed(() =>
  dataset.value ? (dataset.value.all_columns ?? dataset.value.columns) : [],
);
const datasetLoadedColumns = computed(() =>
  dataset.value ? (dataset.value.columns ?? dataset.value.all_columns) : [],
);

const hasDataset = computed(() => dataset.value && dataset.value.data.length > 0);
const isLoadingDataset = computed((): boolean => {
  if (props.historicView) {
    return botStore.activeBot.historyStatus === LoadingStatus.loading;
  }
  return botStore.activeBot.candleDataStatus === LoadingStatus.loading;
});
const noDatasetText = computed((): string => {
  const status = props.historicView
    ? botStore.activeBot.historyStatus
    : botStore.activeBot.candleDataStatus;
  switch (status) {
    case LoadingStatus.not_loaded: return 'Not loaded yet.';
    case LoadingStatus.loading: return 'Loading...';
    case LoadingStatus.success: return 'No data available';
    case LoadingStatus.error: return 'Failed to load data';
    default: return 'Unknown';
  }
});

function refresh() {
  emit('refreshData', props.pair, plotStore.usedColumns);
}

function refreshIfNecessary() {
  if (!hasDataset.value) refresh();
}

function assignFirstPair() {
  const [firstPair] = props.availablePairs;
  if (firstPair) { /* props.pair = firstPair; */ }
}

watch(() => props.availablePairs, () => {
  if (!props.availablePairs.find((p) => p === props.pair)) {
    assignFirstPair();
    refresh();
  }
});

watch(() => plotStore.plotConfig, () => {
  const hasAllColumns = plotStore.usedColumns.some(
    (c) => datasetColumns.value.includes(c) && !datasetLoadedColumns.value.includes(c),
  );
  if (settingsStore.useReducedPairCalls && hasAllColumns) refresh();
});

watch(() => props.timeframe, () => refreshIfNecessary());

watch(
  [() => props.pair, () => props.timeframe, () => props.historicView],
  () => {
    if (props.pair && props.timeframe && !props.historicView) {
      startLiveCandlePolling();
    } else {
      stopLiveCandlePolling();
    }
  },
  { immediate: true },
);

onMounted(() => {
  if (props.pair && props.timeframe && !props.historicView) startLiveCandlePolling();
});
onUnmounted(() => stopLiveCandlePolling());
</script>

<template>
  <div
    class="flex-fill w-full flex-col align-items-stretch flex"
    :class="{
      'h-full': isSinglePairView,
      'h-150 border border-r border-b border-surface-300 dark:border-surface-700': !isSinglePairView,
    }"
  >
    <div class="flex me-0 w-full items-center justify-between">
      <div class="ms-1 md:ms-2 flex flex-wrap md:flex-nowrap items-center gap-1">
        <div class="flex flex-col md:flex-row md:gap-2">
          <div class="flex flex-row flex-wrap gap-2">
            <small v-if="dataset" class="text-sm text-nowrap" title="Long entry signals"
              >Long entries: {{ dataset.enter_long_signals || dataset.buy_signals }}</small>
            <small v-if="dataset" class="text-sm text-nowrap" title="Long exit signals"
              >Long exit: {{ dataset.exit_long_signals || dataset.sell_signals }}</small>
          </div>
          <div class="flex flex-row flex-wrap gap-2">
            <small v-if="dataset && dataset.enter_short_signals" class="text-sm text-nowrap"
              >Short entries: {{ dataset.enter_short_signals }}</small>
            <small v-if="dataset && dataset.exit_short_signals" class="text-sm text-nowrap"
              >Short exits: {{ dataset.exit_short_signals }}</small>
          </div>
        </div>
      </div>
      <div class="flex items-center gap-1">
        {{ pair || 'Pair' }}
        <span
          v-if="liveCandle"
          class="text-xs px-1 py-0.5 rounded font-mono"
          :class="liveCandle.close >= liveCandle.open ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'"
        >
          {{ liveCandle.close.toFixed(liveCandle.close < 1 ? 6 : 2) }}
        </span>
      </div>
      <div v-if="isLoadingDataset">
        <ProgressSpinner class="w-4 h-4" stroke-width="4" small label="Spinning" />
      </div>
      <div v-else class="w-4 h-4"></div>
    </div>
    <div class="h-full flex">
      <div class="min-w-0 w-full flex-1">
        <CandleChart
          v-if="hasDataset"
          :dataset="datasetWithLiveCandle ?? dataset"
          :trades="trades"
          :plot-config="plotStore.plotConfig"
          :heikin-ashi="settingsStore.useHeikinAshiCandles"
          :show-mark-area="settingsStore.showMarkArea"
          :use-u-t-c="settingsStore.timezone === 'UTC'"
          :theme="settingsStore.chartTheme"
          :slider-position="sliderPosition"
          :color-up="colorStore.colorUp"
          :color-down="colorStore.colorDown"
          :start-candle-count="settingsStore.chartDefaultCandleCount"
          :label-side="settingsStore.chartLabelSide"
        />
        <div v-else class="m-auto">
          <ProgressSpinner v-if="isLoadingDataset" class="w-5 h-5" label="Spinning" />
          <div v-else class="text-lg">{{ noDatasetText }}</div>
          <p v-if="botStore.activeBot.historyTakesLonger">
            This is taking longer than expected ... Hold on ...
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
VUEEOF
echo "    Done."
