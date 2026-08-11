import { useMemo, useRef, useState } from 'react'
import type { Unit } from '../types'
import { fmtValue, fmtTick, niceTicks } from '../lib/format'
import { TooltipBox, TipRow, useTooltip } from './Tooltip'

export interface LineSeries {
  id: string
  label: string
  color: string
  values: (number | null)[]
  /** gestippelde referentielijn (bijv. Amsterdam) */
  reference?: boolean
}

interface Props {
  years: number[]
  series: LineSeries[]
  unit: Unit
  height?: number
  /** as vanaf nul forceren (standaard uit: trendverschillen zichtbaar) */
  zeroBased?: boolean
  /** vast y-bereik (bijv. [-1,1] voor correlatiecoëfficiënt) */
  yDomain?: [number, number]
  /** referentielijn op y=0 (bijv. bij correlaties) */
  zeroLine?: boolean
}

const M = { top: 14, right: 128, bottom: 26, left: 46 }

export function LineChart({ years, series, unit, height = 260, zeroBased = false, yDomain, zeroLine }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(640)
  const { tip, show, hide } = useTooltip()
  const [hoverX, setHoverX] = useState<number | null>(null)

  // responsive: meet containerbreedte
  const measure = (el: HTMLDivElement | null) => {
    ;(ref as React.MutableRefObject<HTMLDivElement | null>).current = el
    if (el && el.clientWidth !== w && el.clientWidth > 0) setW(el.clientWidth)
  }

  const iw = Math.max(w - M.left - M.right, 80)
  const ih = height - M.top - M.bottom

  const allVals = series.flatMap((s) => s.values.filter((v): v is number => v != null))
  const dataMin = allVals.length ? Math.min(...allVals) : 0
  const dataMax = allVals.length ? Math.max(...allVals) : 1
  const pad = (dataMax - dataMin || Math.abs(dataMax) || 1) * 0.12
  const yMin = yDomain ? yDomain[0] : zeroBased ? 0 : dataMin - pad
  const yMax = yDomain ? yDomain[1] : dataMax + pad
  const ticks = useMemo(() => niceTicks(yMin, yMax, 4), [yMin, yMax])

  const x = (i: number) => (years.length === 1 ? iw / 2 : (i / (years.length - 1)) * iw)
  const y = (v: number) => ih - ((v - yMin) / (yMax - yMin || 1)) * ih

  // verbindt over ontbrekende jaren heen (bv. RIVM-meetjaren met gaten) i.p.v. de
  // lijn daar te onderbreken — alleen vóór het allereerste datapunt is er niets om
  // een lijn naar te trekken
  const path = (vals: (number | null)[]) => {
    let d = ''
    vals.forEach((v, i) => {
      if (v == null) return
      d += (d === '' ? 'M' : 'L') + `${x(i).toFixed(1)},${y(v).toFixed(1)} `
    })
    return d.trim()
  }

  // eindlabels: alleen tonen als ze niet botsen (anders legenda + tooltip)
  const endLabels = useMemo(() => {
    const ends = series
      .map((s) => {
        const idx = [...s.values].map((v, i) => (v != null ? i : -1)).filter((i) => i >= 0).pop()
        return idx == null || idx < 0 ? null : { s, yPos: y(s.values[idx]!), v: s.values[idx]! }
      })
      .filter(Boolean) as { s: LineSeries; yPos: number; v: number }[]
    ends.sort((a, b) => a.yPos - b.yPos)
    const placed: typeof ends = []
    for (const e of ends) {
      if (placed.every((p) => Math.abs(p.yPos - e.yPos) >= 15)) placed.push(e)
    }
    return placed
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [series, yMin, yMax, ih])

  const onMove = (e: React.PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect()
    const px = e.clientX - rect.left
    const i = Math.round((px / iw) * (years.length - 1))
    const ci = Math.max(0, Math.min(years.length - 1, i))
    setHoverX(ci)
    const rows = [...series]
      .filter((s) => s.values[ci] != null)
      .sort((a, b) => (b.values[ci] ?? 0) - (a.values[ci] ?? 0))
    show(
      M.left + x(ci),
      M.top + ih / 2,
      <>
        <div className="viz-tip-title">{years[ci]}</div>
        {rows.map((s) => (
          <TipRow key={s.id} color={s.color} label={s.label} value={fmtValue(s.values[ci], unit)} />
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
                {fmtTick(t, unit)}
              </text>
            </g>
          ))}
          <line x1={0} x2={iw} y1={ih} y2={ih} stroke="var(--axisline)" strokeWidth={1} />
          {zeroLine && yMin < 0 && yMax > 0 && (
            <line x1={0} x2={iw} y1={y(0)} y2={y(0)} stroke="var(--axisline)" strokeWidth={1.5} strokeDasharray="4 3" />
          )}
          {years.map((yr, i) => (
            <text key={yr} x={x(i)} y={ih + 18} textAnchor="middle" className="viz-axis-text">
              {yr}
            </text>
          ))}

          {hoverX != null && (
            <line
              x1={x(hoverX)}
              x2={x(hoverX)}
              y1={0}
              y2={ih}
              stroke="var(--axisline)"
              strokeWidth={1}
            />
          )}

          {series.map((s) => (
            <g key={s.id}>
              <path
                d={path(s.values)}
                fill="none"
                stroke={s.color}
                strokeWidth={s.reference ? 3 : 2}
                strokeLinejoin="round"
                strokeLinecap="round"
                strokeDasharray={s.reference ? '5 4' : undefined}
                opacity={s.reference ? 0.85 : 1}
              />
              {s.values.map((v, i) =>
                v == null ? null : (
                  <circle
                    key={i}
                    cx={x(i)}
                    cy={y(v)}
                    r={hoverX === i ? 4.5 : 3}
                    fill={s.color}
                    stroke="var(--surface-1)"
                    strokeWidth={2}
                  />
                ),
              )}
            </g>
          ))}

          {endLabels.map(({ s, yPos, v }) => (
            <text
              key={s.id}
              x={iw + 10}
              y={yPos}
              dy="0.32em"
              className="viz-end-label"
            >
              <tspan className="viz-end-value">{fmtValue(v, unit)}</tspan>
              <tspan dx={5} className="viz-end-name">
                {s.label.length > 13 ? s.label.slice(0, 12) + '…' : s.label}
              </tspan>
            </text>
          ))}

          <rect
            x={0}
            y={0}
            width={iw}
            height={ih}
            fill="transparent"
            onPointerMove={onMove}
            onPointerLeave={() => {
              hide()
              setHoverX(null)
            }}
          />
        </g>
      </svg>
      <TooltipBox tip={tip} width={w} />
    </div>
  )
}
