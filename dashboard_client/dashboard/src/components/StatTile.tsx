import type { Unit } from '../types'
import { fmtCompact, fmtDelta } from '../lib/format'

interface Props {
  label: string
  value: number | null
  unit: Unit
  /** verandering t.o.v. eerste beschikbare jaar */
  delta?: number | null
  /** eenheid van de delta (default = unit); bijv. een aantal naast een %-waarde */
  deltaUnit?: Unit
  deltaLabel?: string
  /** kleine trendreeks (één punt per jaar) */
  trend?: (number | null)[]
  /** true = stijging betekent meer vraag (neutraal gekleurd, geen goed/slecht) */
  neutralDelta?: boolean
}

export function StatTile({ label, value, unit, delta, deltaUnit, deltaLabel, trend, neutralDelta = true }: Props) {
  const nums = (trend ?? []).filter((v): v is number => v != null)
  const hasTrend = nums.length >= 2
  const min = Math.min(...nums)
  const max = Math.max(...nums)
  const W = 72
  const H = 26
  const pts = hasTrend
    ? (trend ?? [])
        .map((v, i) =>
          v == null
            ? null
            : `${((i / ((trend!.length - 1) || 1)) * W).toFixed(1)},${(H - 3 - ((v - min) / (max - min || 1)) * (H - 6)).toFixed(1)}`,
        )
        .filter(Boolean)
        .join(' ')
    : ''

  return (
    <div className="stat-tile">
      <div className="stat-label">{label}</div>
      <div className="stat-value-row">
        <span className="stat-value">{fmtCompact(value, unit)}</span>
        {hasTrend && (
          <svg width={W} height={H} className="stat-spark" aria-hidden>
            <polyline points={pts} fill="none" stroke="var(--text-muted)" strokeWidth={1.5} />
            {(() => {
              const lastIdx = (trend ?? []).map((v, i) => (v != null ? i : -1)).filter((i) => i >= 0).pop()
              if (lastIdx == null) return null
              const v = trend![lastIdx]!
              return (
                <circle
                  cx={(lastIdx / ((trend!.length - 1) || 1)) * W}
                  cy={H - 3 - ((v - min) / (max - min || 1)) * (H - 6)}
                  r={3}
                  fill="var(--brand)"
                  stroke="var(--surface-1)"
                  strokeWidth={1.5}
                />
              )
            })()}
          </svg>
        )}
      </div>
      {delta != null && (
        <div className={`stat-delta${neutralDelta ? '' : delta >= 0 ? ' up' : ' down'}`}>
          {fmtDelta(delta, deltaUnit ?? unit)} {deltaLabel}
        </div>
      )}
    </div>
  )
}
