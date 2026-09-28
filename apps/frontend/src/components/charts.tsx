import { AreaSeries, ColorType, CrosshairMode, createChart, type IChartApi, type ISeriesApi, type UTCTimestamp } from 'lightweight-charts';
import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { dateTime } from '../lib/format';

/** Chart tokens (validated reference palette, dark steps). */
export const C = {
  surface: '#1a1a19',
  grid: '#2e2e2b',
  axis: '#8b8a82',
  ink: '#f3f3f1',
  ink2: '#c3c2b7',
  series1: '#3987e5',
  pos: '#3987e5',
  neg: '#e66767',
};

// ---------------------------------------------------------------------------
// Price / liquidity time series (TradingView lightweight-charts)
// ---------------------------------------------------------------------------

export interface TimePoint {
  ts: string;
  value: number | null;
}

export function TimeSeriesChart({ points, formatter, height = 280, color = C.series1, label }: {
  points: TimePoint[];
  formatter: (v: number) => string;
  height?: number;
  color?: string;
  label: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const chartRef = useRef<IChartApi | null>(null);
  const seriesRef = useRef<ISeriesApi<'Area'> | null>(null);
  const [hover, setHover] = useState<{ time: string; value: string } | null>(null);
  const fmt = useRef(formatter);
  fmt.current = formatter;

  const data = useMemo(() => {
    const byTime = new Map<number, number>();
    for (const p of points) {
      if (p.value === null || !Number.isFinite(p.value)) continue;
      byTime.set(Math.floor(Date.parse(p.ts) / 1000), p.value);
    }
    return [...byTime.entries()].sort((a, b) => a[0] - b[0]).map(([time, value]) => ({ time: time as UTCTimestamp, value }));
  }, [points]);

  useEffect(() => {
    if (!ref.current) return;
    const chart = createChart(ref.current, {
      height,
      autoSize: true,
      layout: { background: { type: ColorType.Solid, color: C.surface }, textColor: C.axis, fontSize: 11, attributionLogo: false },
      grid: { vertLines: { visible: false }, horzLines: { color: C.grid } },
      rightPriceScale: { borderVisible: false },
      timeScale: { borderVisible: false, timeVisible: true, secondsVisible: false },
      crosshair: { mode: CrosshairMode.Magnet },
      localization: { priceFormatter: (v: number) => fmt.current(v) },
    });
    const series = chart.addSeries(AreaSeries, {
      lineColor: color,
      lineWidth: 2,
      topColor: `${color}1a`,
      bottomColor: `${color}05`,
      priceLineVisible: false,
      crosshairMarkerRadius: 4,
      crosshairMarkerBorderColor: C.surface,
      crosshairMarkerBorderWidth: 2,
    });
    chart.subscribeCrosshairMove((param) => {
      const d = param.seriesData.get(series) as { value?: number } | undefined;
      if (!param.time || !d || d.value === undefined) {
        setHover(null);
        return;
      }
      setHover({ time: dateTime(new Date((param.time as number) * 1000).toISOString()), value: fmt.current(d.value) });
    });
    chartRef.current = chart;
    seriesRef.current = series;
    return () => {
      chart.remove();
      chartRef.current = null;
      seriesRef.current = null;
    };
  }, [height, color]);

  useEffect(() => {
    seriesRef.current?.setData(data);
    chartRef.current?.timeScale().fitContent();
  }, [data]);

  const last = data[data.length - 1];
  return (
    <div>
      <div className="mb-2 flex items-baseline gap-2 text-xs text-muted" aria-live="polite">
        <span>{label}</span>
        <span className="tabular text-sm font-semibold text-ink">{hover ? hover.value : last ? formatter(last.value) : '—'}</span>
        <span>{hover ? hover.time : last ? 'latest' : ''}</span>
      </div>
      {data.length < 2 ? (
        <div className="flex items-center justify-center rounded-lg border border-dashed border-border text-sm text-muted" style={{ height }}>
          Not enough history yet — points accumulate while the token is monitored.
        </div>
      ) : (
        <div ref={ref} style={{ height }} role="img" aria-label={`${label} over time`} />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Recharts helpers
// ---------------------------------------------------------------------------

const axisProps = {
  stroke: C.axis,
  tick: { fill: C.axis, fontSize: 11 },
  tickLine: false,
  axisLine: { stroke: C.grid },
};

function TooltipBox({ active, payload, label, format, labelFormat }: {
  active?: boolean;
  payload?: { value: number; name: string; color?: string }[];
  label?: string | number;
  format: (v: number) => string;
  labelFormat?: (l: string | number) => string;
}) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-md border border-border bg-surface-2 px-3 py-2 text-xs shadow-lg">
      <div className="mb-1 text-muted">{label !== undefined ? (labelFormat ? labelFormat(label) : String(label)) : ''}</div>
      {payload.map((p) => (
        <div key={p.name} className="tabular flex items-center gap-2 text-ink">
          <span className="inline-block h-2 w-2 rounded-full" style={{ background: p.color ?? C.series1 }} aria-hidden />
          {p.name}: <span className="font-semibold">{format(p.value)}</span>
        </div>
      ))}
    </div>
  );
}

export function LineSeriesChart({ data, dataKey, name, format, height = 240, xKey = 'ts' }: {
  data: Record<string, unknown>[];
  dataKey: string;
  name: string;
  format: (v: number) => string;
  height?: number;
  xKey?: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
        <CartesianGrid stroke={C.grid} vertical={false} />
        <XAxis dataKey={xKey} {...axisProps} tickFormatter={(v: string) => new Date(v).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} minTickGap={40} />
        <YAxis {...axisProps} width={72} tickFormatter={(v: number) => format(v)} domain={['auto', 'auto']} />
        <Tooltip content={<TooltipBox format={format} labelFormat={(l) => dateTime(String(l))} />} cursor={{ stroke: C.axis, strokeWidth: 1 }} />
        <Line type="monotone" dataKey={dataKey} name={name} stroke={C.series1} strokeWidth={2} dot={false} activeDot={{ r: 4, stroke: C.surface, strokeWidth: 2 }} isAnimationActive={false} />
      </LineChart>
    </ResponsiveContainer>
  );
}

/** Drawdown is plotted as a separate chart (never a second axis on the equity chart). */
export function DrawdownChart({ data, height = 160 }: { data: { ts: string; drawdownPct: number }[]; height?: number }) {
  const rows = data.map((d) => ({ ts: d.ts, dd: -Math.abs(d.drawdownPct) }));
  const f = (v: number) => `${v.toFixed(1)}%`;
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={rows} margin={{ top: 8, right: 12, bottom: 0, left: 0 }}>
        <CartesianGrid stroke={C.grid} vertical={false} />
        <XAxis dataKey="ts" {...axisProps} tickFormatter={(v: string) => new Date(v).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} minTickGap={40} />
        <YAxis {...axisProps} width={72} tickFormatter={f} domain={['dataMin', 0]} />
        <Tooltip content={<TooltipBox format={f} labelFormat={(l) => dateTime(String(l))} />} cursor={{ stroke: C.axis, strokeWidth: 1 }} />
        <Area type="monotone" dataKey="dd" name="Drawdown" stroke={C.neg} strokeWidth={2} fill={C.neg} fillOpacity={0.1} isAnimationActive={false} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

/** Bar with a 4px rounded data-end and a square baseline end, for positive and negative values. */
function DivergingBarShape(props: { x?: number; y?: number; width?: number; height?: number; value?: number; fill?: string }) {
  const { x = 0, y = 0, width = 0, height = 0, value = 0 } = props;
  if (!width || !height) return null;
  const w = Math.min(width, 24);
  const cx = x + (width - w) / 2;
  const h = Math.abs(height);
  const top = height < 0 ? y + height : y;
  const r = Math.min(4, h, w / 2);
  const fill = value >= 0 ? C.pos : C.neg;
  // Positive: rounded top (data end). Negative: rounded bottom.
  const d =
    value >= 0
      ? `M${cx},${top + h} L${cx},${top + r} Q${cx},${top} ${cx + r},${top} L${cx + w - r},${top} Q${cx + w},${top} ${cx + w},${top + r} L${cx + w},${top + h} Z`
      : `M${cx},${top} L${cx + w},${top} L${cx + w},${top + h - r} Q${cx + w},${top + h} ${cx + w - r},${top + h} L${cx + r},${top + h} Q${cx},${top + h} ${cx},${top + h - r} Z`;
  return <path d={d} fill={fill} />;
}

export function DailyPnlChart({ data, height = 200 }: { data: { day: string; pnlUsd: number }[]; height?: number }) {
  const f = (v: number) => `${v < 0 ? '−' : ''}$${Math.abs(v).toLocaleString('en-US', { maximumFractionDigits: 0 })}`;
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 12, bottom: 0, left: 0 }} barCategoryGap={4}>
        <CartesianGrid stroke={C.grid} vertical={false} />
        <XAxis dataKey="day" {...axisProps} tickFormatter={(v: string) => v.slice(5)} minTickGap={16} />
        <YAxis {...axisProps} width={72} tickFormatter={f} />
        <ReferenceLine y={0} stroke={C.axis} />
        <Tooltip content={<TooltipBox format={f} />} cursor={{ fill: '#ffffff08' }} />
        <Bar dataKey="pnlUsd" name="Daily P/L" shape={<DivergingBarShape />} isAnimationActive={false} />
      </BarChart>
    </ResponsiveContainer>
  );
}

/** Legend for diverging P/L bars: identity is never color-alone. */
export function PnlLegend() {
  return (
    <div className="flex items-center gap-4 text-xs text-ink-2">
      <span className="inline-flex items-center gap-1.5">
        <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: C.pos }} aria-hidden /> Gain (above zero)
      </span>
      <span className="inline-flex items-center gap-1.5">
        <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: C.neg }} aria-hidden /> Loss (below zero)
      </span>
    </div>
  );
}
