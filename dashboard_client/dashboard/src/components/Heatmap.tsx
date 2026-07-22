import { useRef, useState } from 'react'
import { TooltipBox, useTooltip } from './Tooltip'
import { strength } from '../lib/correlation'

export interface HeatCell {
  r: number | null
  n: number
  ci: { lo: number; hi: number } | null
  p: number | null
  /** true = te weinig gebieden of onzeker -> gedempt/leeg */
  weak: boolean
}

export interface HeatAxis {
  id: string
  label: string
}

interface Props {
  rows: HeatAxis[] // X (socio-demografisch)
  cols: HeatAxis[] // Y (uitkomsten)
  cell: (rowId: string, colId: string) => HeatCell
  onSelect?: (rowId: string, colId: string) => void
  selected?: { x: string; y: string } | null
  /** cellen met n<minN of niet-significant dempen */
  dampUncertain?: boolean
}

// 7-staps divergerend, vast domein [-1,+1] (r is al genormaliseerd)
const DIV = [
  'var(--div-neg-3)', 'var(--div-neg-2)', 'var(--div-neg-1)', 'var(--div-mid)',
  'var(--div-pos-1)', 'var(--div-pos-2)', 'var(--div-pos-3)',
]
function color(r: number | null): string {
  if (r == null) return 'var(--surface-2)'
  const t = Math.max(-1, Math.min(1, r))
  return DIV[Math.max(0, Math.min(6, Math.round(t * 3) + 3))]
}
const fmtR = (r: number | null) => (r == null ? '–' : (r > 0 ? '+' : '') + r.toFixed(2))

const CELL = 30
const GAP = 2

/** Correlatiematrix: X-rijen × Y-kolommen, cel gekleurd op coëfficiënt. */
export function Heatmap({ rows, cols, cell, onSelect, selected, dampUncertain }: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const { tip, show, hide } = useTooltip()
  const [hoverKey, setHoverKey] = useState<string | null>(null)

  const tipFor = (rw: HeatAxis, c: HeatAxis, cl: HeatCell) => (
    <>
      <div className="viz-tip-title">{rw.label} × {c.label}</div>
      <div className="viz-tip-row"><span className="viz-tip-label">correlatie</span><span className="viz-tip-value">{fmtR(cl.r)}</span></div>
      <div className="viz-tip-row"><span className="viz-tip-label">sterkte</span><span className="viz-tip-value">{strength(cl.r)}</span></div>
      <div className="viz-tip-row"><span className="viz-tip-label">gebieden (n)</span><span className="viz-tip-value">{cl.n}</span></div>
      {cl.ci && <div className="viz-tip-row muted"><span className="viz-tip-label">95%-interval</span><span className="viz-tip-value">{fmtR(cl.ci.lo)} … {fmtR(cl.ci.hi)}</span></div>}
    </>
  )

  const labelW = 168
  const headH = 132
  const gridW = cols.length * (CELL + GAP)
  const gridH = rows.length * (CELL + GAP)
  const w = labelW + gridW + 12
  const h = headH + gridH + 8

  return (
    <div className="viz-wrap heatmap-scroll" ref={ref}>
      <svg width={w} height={h} role="group" aria-label="Correlatiematrix gebiedskenmerken versus uitkomsten">
        {/* kolomkoppen (Y, uitkomsten) schuin */}
        {cols.map((c, ci) => {
          const x = labelW + ci * (CELL + GAP) + CELL / 2
          const active = hoverKey?.endsWith(`|${c.id}`) || selected?.y === c.id
          return (
            <text
              key={c.id}
              x={x}
              y={headH - 6}
              transform={`rotate(-45 ${x} ${headH - 6})`}
              className={`heat-collabel${active ? ' active' : ''}`}
            >
              {c.label.length > 22 ? c.label.slice(0, 21) + '…' : c.label}
            </text>
          )
        })}
        {/* rijen */}
        {rows.map((rw, ri) => {
          const y = headH + ri * (CELL + GAP)
          const rowActive = hoverKey?.startsWith(`${rw.id}|`) || selected?.x === rw.id
          return (
            <g key={rw.id}>
              <text x={labelW - 8} y={y + CELL / 2} dy="0.32em" textAnchor="end"
                className={`heat-rowlabel${rowActive ? ' active' : ''}`}>
                {rw.label.length > 24 ? rw.label.slice(0, 23) + '…' : rw.label}
              </text>
              {cols.map((c, ci) => {
                const x = labelW + ci * (CELL + GAP)
                const cl = cell(rw.id, c.id)
                const key = `${rw.id}|${c.id}`
                const isSel = selected?.x === rw.id && selected?.y === c.id
                // n<12 (incl. de 8-11-band) wordt ALTIJD ontzadigd — dit is een
                // vaste ontwerpeis (CORRELATIE-ONTWERP.md), niet afhankelijk van de
                // toggle; de toggle stuurt alleen de optionele significantie-demping (M8)
                const damp = cl.weak || cl.n < 12 || (dampUncertain && cl.p != null && cl.p >= 0.05)
                return (
                  <g key={c.id}>
                    <rect
                      x={x} y={y} width={CELL} height={CELL} rx={3}
                      fill={color(cl.r)}
                      opacity={cl.r == null ? 1 : damp ? 0.32 : 1}
                      stroke={isSel ? 'var(--text-primary)' : 'transparent'}
                      strokeWidth={isSel ? 2 : 0}
                      className={onSelect ? 'heat-cell clickable' : 'heat-cell'}
                      tabIndex={onSelect ? 0 : undefined}
                      role={onSelect ? 'button' : undefined}
                      aria-label={`${rw.label} × ${c.label}: ${cl.r == null ? 'onvoldoende data' : 'correlatie ' + fmtR(cl.r) + ', n=' + cl.n}`}
                      onKeyDown={onSelect ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelect(rw.id, c.id) } } : undefined}
                      onPointerMove={(e) => {
                        setHoverKey(key)
                        const host = ref.current?.getBoundingClientRect()
                        if (!host) return
                        show(e.clientX - host.left, e.clientY - host.top, tipFor(rw, c, cl))
                      }}
                      onPointerLeave={() => { setHoverKey(null); hide() }}
                      onFocus={(e) => {
                        setHoverKey(key)
                        const host = ref.current?.getBoundingClientRect()
                        const box = e.currentTarget.getBoundingClientRect()
                        if (host) show(box.left - host.left + CELL / 2, box.top - host.top + CELL, tipFor(rw, c, cl))
                      }}
                      onBlur={() => { setHoverKey(null); hide() }}
                      onClick={onSelect ? () => onSelect(rw.id, c.id) : undefined}
                    />
                    {rows.length * cols.length <= 120 && cl.r != null && !damp && (
                      <text x={x + CELL / 2} y={y + CELL / 2} dy="0.32em" textAnchor="middle"
                        className="heat-celltext" style={{ fill: Math.abs(cl.r) >= 0.84 ? '#fff' : 'var(--text-primary)' }}
                        pointerEvents="none">
                        {cl.r.toFixed(1).replace('0.', '.').replace('-0', '-')}
                      </text>
                    )}
                  </g>
                )
              })}
            </g>
          )
        })}
      </svg>
      <TooltipBox tip={tip} width={w} />
    </div>
  )
}
