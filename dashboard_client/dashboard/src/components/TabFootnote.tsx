import type { AppState, ViewId } from '../App'
import type { Dataset } from '../types'
import { BronLink } from './BronLink'
import { sectionsForView } from '../lib/verantwoording'
import { SOURCES } from '../lib/sources'

/**
 * Compacte, per-tabblad "Bronnen & verantwoording"-sectie, standaard
 * ingeklapt. Gebruikt dezelfde databron (VERANTWOORDING_SECTIONS / SOURCES)
 * als het Verantwoording- en Bronnen-tabblad, gefilterd op dit tabblad — geen
 * los dubbel geschreven tekst.
 */
export function TabFootnote({ viewId, ds, state }: { viewId: ViewId; ds: Dataset; state: AppState }) {
  const sections = sectionsForView(viewId)
  const sources = SOURCES.filter((s) => s.relatedViews?.includes(viewId))
  if (sections.length === 0 && sources.length === 0) return null

  return (
    <details className="tab-footnote">
      <summary>Bronnen &amp; verantwoording</summary>
      <div className="tab-footnote-body">
        {sections.map((sec) => (
          <div key={sec.id} className="tab-footnote-block">
            <h4>{sec.title}</h4>
            {sec.render(state, ds)}
          </div>
        ))}
        {sources.length > 0 && (
          <p className="tab-footnote-sources">
            Bronnen:{' '}
            {sources.map((s, i) => (
              <span key={s.id}>
                <BronLink state={state} id={s.id}>
                  {s.name}
                </BronLink>
                {i < sources.length - 1 ? ', ' : ''}
              </span>
            ))}
          </p>
        )}
        <button
          type="button"
          className="bron-link"
          onClick={() => state.openVerantwoording(sections[0]?.id)}
        >
          Bekijk volledige verantwoording →
        </button>
      </div>
    </details>
  )
}
