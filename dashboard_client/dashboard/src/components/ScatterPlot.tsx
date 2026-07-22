import { useRef, useState } from 'react'
import { TooltipBox, useTooltip } from './Tooltip'
import { niceTicks } from '../lib/format'

export interface ScatterPoint {
  code: string
  label: string
  x: number
  y: number
  /** kleurwaarde (bijv. de index) voor de vulling */
  value?: number | null
  highlight?: boolean
}

interface Props {
  points: ScatterPoint[]
  xLabel: string
  yLabel: string
  xUnit?: string
  yUnit?: string
  /** kwadrantlijnen op deze x/y (bijv. 0 of het stedelijk gemiddelde) */
  xRef?: number
  yRef?: number
  /** labels voor de vier kwadranten, met de klok mee vanaf rechtsboven */
  quadrants?: { tr: string; br: string; bl: string; tl: string }
  fmtX: (v: number) => string
  fmtY: (v: number) => string
  colorFor: (v: number | null | undefined) => string
  height?: number
  onSelect?: (code: string) => void
  onHover?: (code: string | null) => void
  hovered?: string | null
  /** optionele lineaire hulplijn (OLS): y = slope·x + intercept */
  trendLine?: { slope: number; intercept: number } | null
}

const M = { top: 16, right: 18, bottom: 44, left: 56 }

/** Spreidingsdiagram met kwadranten — voor het WOZ × lage-inkomens verdringingspatroon. */
export function ScatterPlot({
  points, xLabel, yLabel, xRef, yRef, quadrants,
  fmtX, fmtY, colorFor, height = 420, onSelect, onHover, hovered, trendLine,
}: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(560)
  const { tip, show, hide } = useTooltip()

  const measure = (el: HTMLDivElement | null) => {
    ;(ref as React.MutableRefObject<HTMLDivElement | null>).current = el
    if (el && el.clientWidth !== w && el.clientWidth > 0) setW(el.clientWidth)
  }

  const iw = Math.max(w - M.left - M.right, 80)
  const ih = height - M.top - M.bottom
  // alleen eindige punten meenemen; degeneratie mag de grafiek nooit laten crashen
  const finite = points.filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y))
  const xs = finite.map((p) => p.x)
  const ys = finite.map((p) => p.y)
  const domain1D = (a: number[], ref: number | undefined, r: number) => {
    const seed = a.length ? a : [0]
    const lo = Math.min(...seed, ref ?? Infinity)
    const hi = Math.max(...seed, ref ?? -Infinity)
    const m = (hi - lo || Math.abs(hi) || 1) * r
    return [lo - m, hi + m] as const
  }
  const [xMin, xMax] = domain1D(xs, xRef, 0.08)
  const [yMin, yMax] = domain1D(ys, yRef, 0.08)

  if (finite.length === 0) {
    return <p className="view-sub">Geen vergelijkbare waarden voor beide assen in deze selectie.</p>
  }

  const sx = (v: number) => ((v - xMin) / (xMax - xMin || 1)) * iw
  const sy = (v: number) => ih - ((v - yMin) / (yMax - yMin || 1)) * ih
  const xTicks = niceTicks(xMin, xMax, 4)
  const yTicks = niceTicks(yMin, yMax, 4)
  const xr = xRef != null ? sx(xRef) : null
  const yr = yRef != null ? sy(yRef) : null

  return (
    <div className="viz-wrap" ref={measure}>
      <svg width="100%" height={height} viewBox={`0 0 ${w} ${height}`} role="group" aria-label={`${xLabel} versus ${yLabel}`}>
        <g transform={`translate(${M.left},${M.top})`}>
          {/* kwadrantvlakken */}
          {xr != null && yr != null && (
            <>
              <rect x={xr} y={0} width={iw - xr} height={yr} fill="var(--brand-wash)" />
              <rect x={0} y={yr} width={xr} height={ih - yr} fill="var(--surface-2)" opacity={0.5} />
            </>
          )}
          {/* gridlijnen */}
          {xTicks.map((t) => (
            <g key={`x${t}`} transform={`translate(${sx(t)},0)`}>
              <line y1={0} y2={ih} stroke="var(--gridline)" strokeWidth={1} />
              <text y={ih + 16} textAnchor="middle" className="viz-axis-text">{fmtX(t)}</text>
            </g>
          ))}
          {yTicks.map((t) => (
            <g key={`y${t}`} transform={`translate(0,${sy(t)})`}>
              <line x1={0} x2={iw} stroke="var(--gridline)" strokeWidth={1} />
              <text x={-8} dy="0.32em" textAnchor="end" className="viz-axis-text">{fmtY(t)}</text>
            </g>
          ))}
          {/* referentie-assen (kwadrantscheiding) */}
          {xr != null && <line x1={xr} x2={xr} y1={0} y2={ih} stroke="var(--axisline)" strokeWidth={1.5} strokeDasharray="4 3" />}
          {yr != null && <line x1={0} x2={iw} y1={yr} y2={yr} stroke="var(--axisline)" strokeWidth={1.5} strokeDasharray="4 3" />}
          {/* kwadrantlabels */}
          {quadrants && (
            <>
              <text x={iw - 4} y={12} textAnchor="end" className="viz-quad-label">{quadrants.tr}</text>
              <text x={iw - 4} y={ih - 6} textAnchor="end" className="viz-quad-label">{quadrants.br}</text>
              <text x={4} y={ih - 6} textAnchor="start" className="viz-quad-label">{quadrants.bl}</text>
              <text x={4} y={12} textAnchor="start" className="viz-quad-label">{quadrants.tl}</text>
            </>
          )}
          {/* lineaire hulplijn (OLS), geclipt op het x-domein */}
          {trendLine && (() => {
            const y0 = trendLine.slope * xMin + trendLine.intercept
            const y1 = trendLine.slope * xMax + trendLine.intercept
            const cy0 = Math.max(0, Math.min(ih, sy(y0)))
            const cy1 = Math.max(0, Math.min(ih, sy(y1)))
            return (
              <line
                x1={sx(xMin)} y1={cy0} x2={sx(xMax)} y2={cy1}
                stroke="var(--text-secondary)" strokeWidth={1.5} strokeDasharray="5 4"
                pointerEvents="none"
              />
            )
          })()}
          {/* punten */}
          {finite.map((p) => {
            const isHover = hovered === p.code
            return (
              <circle
                key={p.code}
                cx={sx(p.x)}
                cy={sy(p.y)}
                r={p.highlight || isHover ? 8 : 6}
                fill={colorFor(p.value)}
                stroke={p.highlight || isHover ? 'var(--text-primary)' : 'var(--surface-1)'}
                strokeWidth={p.highlight || isHover ? 2.5 : 2}
                className={onSelect ? 'viz-dot clickable' : 'viz-dot'}
                tabIndex={onSelect ? 0 : undefined}
                role={onSelect ? 'button' : undefined}
                aria-label={`${p.label}: ${xLabel} ${fmtX(p.x)}, ${yLabel} ${fmtY(p.y)}`}
                onKeyDown={onSelect ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(p.code) } } : undefined}
                onFocus={(e) => {
                  onHover?.(p.code)
                  const host = ref.current?.getBoundingClientRect()
                  const box = e.currentTarget.getBoundingClientRect()
                  if (host) show(box.left - host.left + box.width / 2, box.top - host.top, tipContent(p))
                }}
                onBlur={() => { onHover?.(null); hide() }}
                onPointerMove={(e) => {
                  onHover?.(p.code)
                  const host = ref.current?.getBoundingClientRect()
                  if (host) show(e.clientX - host.left, e.clientY - host.top, tipContent(p))
                }}
                onPointerLeave={() => { onHover?.(null); hide() }}
                onClick={onSelect ? () => onSelect(p.code) : undefined}
              />
            )
          })}
          <text x={iw / 2} y={ih + 38} textAnchor="middle" className="viz-axis-title">{xLabel} →</text>
        </g>
        <text x={14} y={M.top + ih / 2} textAnchor="middle" className="viz-axis-title"
          transform={`rotate(-90 14 ${M.top + ih / 2})`}>{yLabel} →</text>
      </svg>
      <TooltipBox tip={tip} width={w} />
    </div>
  )

  function tipContent(p: ScatterPoint) {
    return (
      <>
        <div className="viz-tip-title">{p.label}</div>
        <div className="viz-tip-row"><span className="viz-tip-label">{xLabel}</span><span className="viz-tip-value">{fmtX(p.x)}</span></div>
        <div className="viz-tip-row"><span className="viz-tip-label">{yLabel}</span><span className="viz-tip-value">{fmtY(p.y)}</span></div>
      </>
    )
  }
}
