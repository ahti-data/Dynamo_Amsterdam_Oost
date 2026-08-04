import { useRef, useState } from 'react'
import type { Unit } from '../types'
import { fmtValue } from '../lib/format'
import { TooltipBox, TipRow, useTooltip } from './Tooltip'

export interface BarRow {
  code: string
  label: string
  value: number | null
  /** referentierij (bijv. Amsterdam-gemiddelde) — gemarkeerd weergegeven */
  reference?: boolean
  highlight?: boolean
}

interface Props {
  rows: BarRow[]
  unit: Unit
  color?: string
  /** verticale referentielijn (bijv. Amsterdam-waarde) */
  referenceLine?: { value: number; label: string }
  onSelect?: (code: string) => void
  /** koppeling met de kaart: meld welke rij onder de muis ligt */
  onHover?: (code: string | null) => void
  /** koppeling met de kaart: licht deze rij op (hover elders) */
  hovered?: string | null
  /** titel onder de x-as (bijv. de naam/eenheid van de indicator) */
  xAxisLabel?: string
  /** vaste totaalhoogte (bijv. om gelijk te lopen met een naastgelegen kaart); staven schalen mee */
  height?: number
}

const BAR_H = 20
const GAP = 8

/** Horizontale staafgrafiek voor wijkvergelijking, gesorteerd aanleveren. */
export function BarChart({
  rows,
  unit,
  color = 'var(--series-1)',
  referenceLine,
  onSelect,
  onHover,
  hovered,
  xAxisLabel,
  height: fixedHeight,
}: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(640)
  const { tip, show, hide } = useTooltip()
  const [hover, setHover] = useState<string | null>(null)

  const measure = (el: HTMLDivElement | null) => {
    ;(ref as React.MutableRefObject<HTMLDivElement | null>).current = el
    if (el && el.clientWidth !== w && el.clientWidth > 0) setW(el.clientWidth)
  }

  const axisSpace = xAxisLabel ? 20 : 4
  const M = { top: 4, right: 76, bottom: axisSpace, left: 168 }
  const iw = Math.max(w - M.left - M.right, 60)
  const minHeight = M.top + rows.length * (BAR_H + GAP) - GAP + M.bottom
  const height = Math.max(fixedHeight ?? minHeight, minHeight)
  // extra ruimte boven de laatste rij evenredig verdelen zodat staven de vaste hoogte opvullen
  const rowStep = rows.length > 0 ? (height - M.top - M.bottom + GAP) / rows.length : BAR_H + GAP
  const barH = Math.max(rowStep - GAP, BAR_H)
  const vals = rows.map((r) => r.value).filter((v): v is number => v != null)
  // domein omvat 0 én negatieve waarden (relatieve afwijkingen onder referentie)
  const maxV = Math.max(...vals, referenceLine?.value ?? 0, 0.0001)
  const minV = Math.min(...vals, 0)
  const span = maxV - minV || 1
  const xScale = (v: number) => ((v - minV) / span) * iw
  const x0 = xScale(0)

  /** staaf vanaf de nullijn, 4px afgerond data-uiteinde, recht aan de basis */
  const barPath = (v: number): string => {
    const bw = Math.max(Math.abs(xScale(v) - x0), 2)
    const r = Math.min(4, bw)
    if (v >= 0)
      return `M${x0},0 h${bw - r} a${r},${r} 0 0 1 ${r},${r} v${barH - 2 * r} a${r},${r} 0 0 1 -${r},${r} h${-(bw - r)} Z`
    return `M${x0},0 h${-(bw - r)} a${r},${r} 0 0 0 -${r},${r} v${barH - 2 * r} a${r},${r} 0 0 0 ${r},${r} h${bw - r} Z`
  }

  return (
    <div className="viz-wrap" ref={measure}>
      <svg width="100%" height={height} viewBox={`0 0 ${w} ${height}`} role="img">
        <g transform={`translate(${M.left},${M.top})`}>
          {rows.map((r, i) => {
            const yPos = i * rowStep
            const isHover = hover === r.code || hovered === r.code
            const neg = (r.value ?? 0) < 0
            const tipX = r.value == null ? x0 : xScale(r.value)
            return (
              <g
                key={r.code}
                transform={`translate(0,${yPos})`}
                className={onSelect ? 'viz-bar-row clickable' : 'viz-bar-row'}
                onPointerMove={(e) => {
                  setHover(r.code)
                  onHover?.(r.code)
                  const host = ref.current?.getBoundingClientRect()
                  if (!host) return
                  show(
                    e.clientX - host.left,
                    e.clientY - host.top,
                    <TipRow color={color} label={r.label} value={fmtValue(r.value, unit)} />,
                  )
                }}
                onPointerLeave={() => {
                  setHover(null)
                  onHover?.(null)
                  hide()
                }}
                onClick={onSelect ? () => onSelect(r.code) : undefined}
              >
                <rect x={-M.left} y={-GAP / 2} width={w} height={rowStep} fill="transparent" />
                <text
                  x={-10}
                  y={barH / 2}
                  dy="0.32em"
                  textAnchor="end"
                  className={`viz-bar-label${r.highlight || isHover ? ' strong' : ''}${r.reference ? ' ref' : ''}`}
                >
                  {r.label.length > 24 ? r.label.slice(0, 23) + '…' : r.label}
                </text>
                {r.value != null && (
                  <path
                    d={barPath(r.value)}
                    fill={color}
                    opacity={r.reference ? 0.38 : isHover ? 0.85 : 1}
                  />
                )}
                {(() => {
                  // negatief label links van de staafpunt; te weinig ruimte
                  // (botst met wijknaam) -> binnenin de staaf (die is dan breed)
                  const inside = neg && tipX < 60
                  return (
                    <text
                      x={inside ? tipX + 6 : neg ? tipX - 8 : tipX + 8}
                      y={barH / 2}
                      dy="0.32em"
                      textAnchor={neg && !inside ? 'end' : 'start'}
                      className={`viz-bar-value${inside ? ' inverse' : ''}`}
                    >
                      {fmtValue(r.value, unit)}
                    </text>
                  )
                })()}
              </g>
            )
          })}
          {minV < 0 && (
            <line
              x1={x0}
              x2={x0}
              y1={-2}
              y2={rows.length * rowStep - GAP + 2}
              stroke="var(--axisline)"
              strokeWidth={1}
            />
          )}
          {referenceLine && (
            <g>
              <line
                x1={xScale(referenceLine.value)}
                x2={xScale(referenceLine.value)}
                y1={-2}
                y2={rows.length * rowStep - GAP + 2}
                stroke="var(--text-secondary)"
                strokeWidth={1}
                strokeDasharray="4 3"
              />
              <text
                x={xScale(referenceLine.value)}
                y={rows.length * rowStep + 2}
                textAnchor="middle"
                className="viz-axis-text"
              >
                {referenceLine.label}
              </text>
            </g>
          )}
          {xAxisLabel && (
            <text
              x={iw / 2}
              y={rows.length * rowStep - GAP + 16}
              textAnchor="middle"
              className="viz-axis-text"
            >
              {xAxisLabel}
            </text>
          )}
        </g>
      </svg>
      <TooltipBox tip={tip} width={w} />
    </div>
  )
}
