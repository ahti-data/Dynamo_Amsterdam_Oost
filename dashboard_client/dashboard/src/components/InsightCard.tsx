import type { NavTarget } from '../App'

export interface InsightProfileDim {
  dim: string
  label: string
  value: string
  vsRef?: string
}

export interface InsightLink {
  view: NavTarget['view']
  scope: string
  level: NavTarget['level']
  indicatorId?: string
  xId?: string
  yId?: string
  year: number
  label?: string
}

export interface InsightCardData {
  title: string
  persona: string
  profile: InsightProfileDim[]
  finding: string
  method: string
  why: string
  confidence: 'hoog' | 'middel' | 'laag'
  links: InsightLink[]
}

/**
 * Eén doelgroepdossier, standaard ingeklapt tot titel + vertrouwen + een
 * korte samenvatting. Uitgeklapt krijgt elk onderdeel (Doelgroep, Profiel,
 * Bevindingen, Voor Dynamo, Methode) een eigen kopje i.p.v. één blok tekst.
 */
export function InsightCard({
  insight,
  linkLabel,
  onNavigate,
}: {
  insight: InsightCardData
  linkLabel: (l: InsightLink) => string
  onNavigate: (l: InsightLink) => void
}) {
  return (
    <details className="insight-card">
      <summary className="insight-summary">
        <span className="insight-summary-head">
          <span className={`conf conf-${insight.confidence}`} title={`vertrouwen: ${insight.confidence}`}>
            {insight.confidence}
          </span>
          <span className="insight-title">{insight.title}</span>
        </span>
        <span className="insight-summary-snippet">{insight.persona}</span>
      </summary>

      <div className="insight-body">
        <section className="insight-section">
          <h4>Doelgroep</h4>
          <p className="insight-persona">{insight.persona}</p>
        </section>

        {insight.profile?.length > 0 && (
          <section className="insight-section">
            <h4>Profiel</h4>
            <div className="profile-chips" aria-label="Profiel">
              {insight.profile.map((p, k) => (
                <span key={k} className="profile-chip" title={p.label + (p.vsRef ? ` — ${p.vsRef}` : '')}>
                  <span className="pc-label">{p.label}</span>
                  <span className="pc-value">{p.value}</span>
                </span>
              ))}
            </div>
          </section>
        )}

        <section className="insight-section">
          <h4>Bevindingen</h4>
          <p className="insight-finding">{insight.finding}</p>
        </section>

        <section className="insight-section">
          <h4>Voor Dynamo</h4>
          <p className="insight-why">{insight.why}</p>
        </section>

        <details className="insight-evidence">
          <summary>Methode &amp; onderbouwing</summary>
          <p>{insight.method}</p>
        </details>

        <div className="insight-links">
          {insight.links.map((l, k) => (
            <button key={k} className="insight-link" onClick={() => onNavigate(l)}>
              → {linkLabel(l)}
            </button>
          ))}
        </div>
      </div>
    </details>
  )
}
