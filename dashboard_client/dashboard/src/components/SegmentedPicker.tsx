import type { ReactNode } from 'react'

export interface SegmentedOption {
  id: string
  label: ReactNode
}

/**
 * Enkelvoudige-keuze rij met de bestaande .seg-stijl (geen "bubbels" die
 * over meerdere regels wrappen) i.p.v. de losstaande .chip-row-implementaties
 * die eerder per view gedupliceerd waren. Bij overvloed schuift de rij
 * horizontaal (.seg-wide) in plaats van te wrappen.
 */
export function SegmentedPicker({
  options,
  value,
  onChange,
  ariaLabel,
  asTabs = false,
}: {
  options: SegmentedOption[]
  value: string
  onChange: (id: string) => void
  ariaLabel: string
  /** true = tab-widget-semantiek (role=tab/tablist); false = filter (role=group) */
  asTabs?: boolean
}) {
  return (
    <div className="seg seg-wide" role={asTabs ? 'tablist' : 'group'} aria-label={ariaLabel}>
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          role={asTabs ? 'tab' : undefined}
          aria-selected={asTabs ? o.id === value : undefined}
          aria-pressed={asTabs ? undefined : o.id === value}
          className={o.id === value ? 'active' : ''}
          onClick={() => onChange(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}
