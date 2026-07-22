import { useState, useCallback, type ReactNode } from 'react'

export interface TooltipState {
  x: number
  y: number
  content: ReactNode
}

/** Zwevende tooltip binnen een relatief gepositioneerde kaart-container. */
export function useTooltip() {
  const [tip, setTip] = useState<TooltipState | null>(null)
  const show = useCallback((x: number, y: number, content: ReactNode) => {
    setTip({ x, y, content })
  }, [])
  const hide = useCallback(() => setTip(null), [])
  return { tip, show, hide }
}

export function TooltipBox({ tip, width }: { tip: TooltipState | null; width: number }) {
  if (!tip) return null
  const flip = tip.x > width * 0.62
  return (
    <div
      className="viz-tooltip"
      style={{
        left: tip.x,
        top: tip.y,
        transform: flip ? 'translate(calc(-100% - 14px), -50%)' : 'translate(14px, -50%)',
      }}
      role="status"
    >
      {tip.content}
    </div>
  )
}

/** Tooltipregel: waarde prominent, label secundair, lijnkleur-key. */
export function TipRow({
  color,
  label,
  value,
  muted,
}: {
  color?: string
  label: string
  value: string
  muted?: boolean
}) {
  return (
    <div className={`viz-tip-row${muted ? ' muted' : ''}`}>
      {color ? <span className="viz-tip-key" style={{ background: color }} /> : null}
      <span className="viz-tip-label">{label}</span>
      <span className="viz-tip-value">{value}</span>
    </div>
  )
}
