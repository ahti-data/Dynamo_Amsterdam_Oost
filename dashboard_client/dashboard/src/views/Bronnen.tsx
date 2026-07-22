import { useEffect, useRef } from 'react'
import type { AppState } from '../App'
import { SOURCES, STATUS_META, STATUS_ORDER, type Source } from '../lib/sources'

function SourceCard({ src, highlighted }: { src: Source; highlighted: boolean }) {
  return (
    <article id={`bron-${src.id}`} className={`bron-card${highlighted ? ' is-target' : ''}`}>
      <header className="bron-card-head">
        <h3>{src.name}</h3>
        <span className="bron-provider">{src.provider}</span>
      </header>

      <p className="bron-content">{src.content}</p>

      <dl className="bron-meta">
        {src.usedFor && (
          <>
            <dt>Gebruikt voor</dt>
            <dd>{src.usedFor}</dd>
          </>
        )}
        <dt>Dekking</dt>
        <dd>{src.coverage}</dd>
        {src.note && (
          <>
            <dt>Let op</dt>
            <dd>{src.note}</dd>
          </>
        )}
        <dt>Licentie</dt>
        <dd>{src.license}</dd>
      </dl>

      <div className="bron-links">
        {(src.links ?? [{ label: 'Naar de bron', url: src.url }]).map((l) => (
          <a key={l.url} href={l.url} target="_blank" rel="noopener noreferrer" className="bron-ext">
            {l.label} ↗
          </a>
        ))}
      </div>
    </article>
  )
}

export function Bronnen({ state }: { state: AppState }) {
  const target = state.sourceAnchor
  const scrolledFor = useRef<string | null>(null)

  useEffect(() => {
    if (!target) return
    // pas scrollen wanneer het doel verandert, en het anker daarna vrijgeven
    if (scrolledFor.current === target) return
    scrolledFor.current = target
    const el = document.getElementById(`bron-${target}`)
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    const t = setTimeout(() => state.clearSourceAnchor(), 2400)
    return () => clearTimeout(t)
  }, [target, state])

  return (
    <div className="prose bronnen">
      <h1 className="view-title">Bronnen</h1>
      <p className="view-sub">
        Alle databronnen achter deze monitor, met een koppeling naar de oorspronkelijke vindplaats.
        De monitor toont zelf de <strong>kernbronnen</strong>; de overige bronnen zijn geïnventariseerd
        en gedownload voor toekomstige uitbreiding. Uitgebreide inhoud, kwaliteit en licenties staan in{' '}
        <code>external-data/DATA_CATALOGUS.md</code>.
      </p>

      {STATUS_ORDER.map((status) => {
        const items = SOURCES.filter((s) => s.status === status)
        if (items.length === 0) return null
        return (
          <section key={status} className="bron-group">
            <h2>{STATUS_META[status].label}</h2>
            <p className="bron-group-blurb">{STATUS_META[status].blurb}</p>
            <div className="bron-cards">
              {items.map((s) => (
                <SourceCard key={s.id} src={s} highlighted={target === s.id} />
              ))}
            </div>
          </section>
        )
      })}

      <h2>Herkomst en bronvermelding</h2>
      <ul>
        <li>
          De CBS-bronnen zijn open data onder CC BY 4.0; vermeld bij hergebruik het CBS en de tabel.
        </li>
        <li>
          RIVM-tabellen zijn CC BY 4.0 (bronvermelding RIVM/CBS). Amsterdamse en Vektis-bronnen hebben
          per bron afwijkende voorwaarden — controleer de licentie opnieuw vóór externe publicatie.
        </li>
        <li>
          De downloads zijn een snapshot van 10 juli 2026. Reproduceerbaar via{' '}
          <code>external-data/download_sources.py</code>.
        </li>
      </ul>
    </div>
  )
}
