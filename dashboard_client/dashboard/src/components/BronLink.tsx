import type { AppState } from '../App'
import { findSource } from '../lib/sources'

/**
 * Inline, klikbare koppeling die het Bronnen-tabblad opent en direct naar de
 * betreffende dataset scrolt. Gebruikt overal in de tool op logische plekken
 * (Verantwoording, Samenhang, Inzichten, footer …).
 */
export function BronLink({
  state,
  id,
  children,
}: {
  state: AppState
  /** specifieke dataset; leeg = open het Bronnen-tabblad zonder te scrollen */
  id?: string
  children?: React.ReactNode
}) {
  const src = id ? findSource(id) : undefined
  const label = children ?? src?.name ?? 'Bronnen'
  return (
    <button
      type="button"
      className="bron-link"
      onClick={() => state.openSource(id)}
      title={src ? `Naar bron: ${src.name}` : 'Naar het tabblad Bronnen'}
    >
      {label}
    </button>
  )
}
