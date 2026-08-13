import { useMemo, useRef, useState } from 'react'
import { fmtValue, niceTicks } from '../lib/format'
import { TooltipBox, TipRow, useTooltip } from './Tooltip'
import type { ForecastPoint } from '../lib/forecast'

export interface ForecastSeries {
  id: string
  label: string
  color: string
  points: ForecastPoint[]
  reference?: boolean
}

interface Props {
  series: ForecastSeries[]
  /** laatste waarnemingsjaar — grens tussen waarneming (vol) en prognose (stippel) */
  lastObsYear: number
  height?: number
}

const M = { top: 16, right: 132, bottom: 28, left: 48 }

/**
 * Chart op een echte jaar-as: waarnemingen als volle lijn, officiële prognose
 * als stippellijn (geen band — de bronnen publiceren geen interval). Een
 * verticale "nu"-lijn markeert het laatste waarnemingsjaar.
 */
export function ForecastChart({ series, lastObsYear, height = 340 }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(660)
  const { tip, show, hide } = useTooltip()
  const [hoverYear, setHoverYear] = useState<number | null>(null)

  const measure = (el: HTMLDivElement | null) => {
    ;(ref as React.MutableRefObject<HTMLDivElement | null>).current = el
    if (el && el.clientWidth !== w && el.clientWidth > 0) setW(el.clientWidth)
  }

  const iw = Math.max(w - M.left - M.right, 80)
  const ih = height - M.top - M.bottom

  const allYears = useMemo(() => {
    const s = new Set<number>()
    series.forEach((se) => se.points.forEach((p) => s.add(p.year)))
    return [...s].sort((a, b) => a - b)
  }, [series])
  const xMin = allYears[0] ?? lastObsYear
  const xMax = allYears[allYears.length - 1] ?? lastObsYear

  const allVals = series.flatMap((s) => s.points.map((p) => p.value))
  const dataMin = allVals.length ? Math.min(...allVals) : 0
  const dataMax = allVals.length ? Math.max(...allVals) : 1
  const pad = (dataMax - dataMin || Math.abs(dataMax) || 1) * 0.12
  const yMin = Math.max(0, dataMin - pad)
  const yMax = dataMax + pad
  const ticks = useMemo(() => niceTicks(yMin, yMax, 4), [yMin, yMax])

  const x = (yr: number) => (xMax === xMin ? iw / 2 : ((yr - xMin) / (xMax - xMin)) * iw)
  const y = (v: number) => ih - ((v - yMin) / (yMax - yMin || 1)) * ih

  const line = (pts: { year: number; v: number }[]) =>
    pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(p.year).toFixed(1)},${y(p.v).toFixed(1)}`).join(' ')

  const onMove = (e: React.PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect()
    const px = e.clientX - rect.left
    const yr = xMin + (px / iw) * (xMax - xMin)
    const nearest = allYears.reduce((b, c) => (Math.abs(c - yr) < Math.abs(b - yr) ? c : b), allYears[0])
    setHoverYear(nearest)
    const rows = series
      .map((s) => ({ s, p: s.points.find((pp) => pp.year === nearest) }))
      .filter((r) => r.p)
      .sort((a, b) => (b.p!.value - a.p!.value))
    show(
      M.left + x(nearest),
      M.top + ih / 2,
      <>
        <div className="viz-tip-title">
          {nearest} {nearest > lastObsYear ? '· officiële prognose' : ''}
        </div>
        {rows.map(({ s, p }) => (
          <TipRow key={s.id} color={s.color} label={s.label} value={fmtValue(p!.value, 'aantal')} />
        ))}
      </>,
    )
  }

  return (
    <div className="viz-wrap" ref={measure}>
      <svg width="100%" height={height} viewBox={`0 0 ${w} ${height}`} role="img">
        <g transform={`translate(${M.left},${M.top})`}>
          {ticks.map((t) => (
            <g key={t} transform={`translate(0,${y(t)})`}>
              <line x1={0} x2={iw} stroke="var(--gridline)" strokeWidth={1} />
              <text x={-8} dy="0.32em" textAnchor="end" className="viz-axis-text">
                {t >= 1000 ? `${(t / 1000).toLocaleString('nl-NL')}k` : t.toLocaleString('nl-NL')}
              </text>
            </g>
          ))}
          <line x1={0} x2={iw} y1={ih} y2={ih} stroke="var(--axisline)" strokeWidth={1} />
          {allYears
            .filter((yr, i) => i % 2 === 0 || yr === lastObsYear || yr === xMax)
            .map((yr) => (
              <text key={yr} x={x(yr)} y={ih + 18} textAnchor="middle" className="viz-axis-text">
                {yr}
              </text>
            ))}

          {/* "nu"-lijn: grens waarneming ↔ prognose */}
          <line x1={x(lastObsYear)} x2={x(lastObsYear)} y1={0} y2={ih} stroke="var(--axisline)" strokeWidth={1} strokeDasharray="3 3" />
          <text x={x(lastObsYear)} y={-4} textAnchor="middle" className="viz-axis-text">
            nu
          </text>

          {/* lijnen: waarneming vol, prognose gestippeld */}
          {series.map((s) => {
            const obs = s.points.filter((p) => !p.forecast).map((p) => ({ year: p.year, v: p.value }))
            const lastObs = obs[obs.length - 1]
            const fc = s.points.filter((p) => p.forecast).map((p) => ({ year: p.year, v: p.value }))
            const fcWithBridge = lastObs ? [lastObs, ...fc] : fc
            return (
              <g key={s.id}>
                <path
                  d={line(obs)}
                  fill="none"
                  stroke={s.color}
                  strokeWidth={s.reference ? 1.75 : 2.25}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                  opacity={s.reference ? 0.8 : 1}
                  strokeDasharray={s.reference ? '5 4' : undefined}
                />
                <path
                  d={line(fcWithBridge)}
                  fill="none"
                  stroke={s.color}
                  strokeWidth={s.reference ? 1.75 : 2.25}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                  strokeDasharray="2 4"
                  opacity={s.reference ? 0.7 : 0.9}
                />
                {s.points.map((p) => (
                  <circle
                    key={p.year}
                    cx={x(p.year)}
                    cy={y(p.value)}
                    // elk punt (waarneming én officiële prognose) is een hard getal,
                    // geen model-doortrekking — dus altijd een zichtbare marker
                    r={hoverYear === p.year ? 4 : 2.6}
                    fill={s.color}
                    stroke="var(--surface-1)"
                    strokeWidth={1.5}
                  />
                ))}
              </g>
            )
          })}

          {/* eindlabels bij het laatste prognosejaar */}
          {series.map((s) => {
            const last = s.points[s.points.length - 1]
            if (!last) return null
            return (
              <text key={`lab-${s.id}`} x={iw + 8} y={y(last.value)} dy="0.32em" className="viz-end-label">
                <tspan className="viz-end-value">{fmtValue(last.value, 'aantal')}</tspan>
                <tspan dx={5} className="viz-end-name">
                  {s.label.length > 12 ? s.label.slice(0, 11) + '…' : s.label}
                </tspan>
              </text>
            )
          })}

          <rect x={0} y={0} width={iw} height={ih} fill="transparent" onPointerMove={onMove} onPointerLeave={() => { hide(); setHoverYear(null) }} />
        </g>
      </svg>
      <TooltipBox tip={tip} width={w} />
    </div>
  )
}
