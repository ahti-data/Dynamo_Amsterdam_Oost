import { useEffect, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, NavTarget } from '../App'
import { indicatorById, regionName } from '../lib/data'
import { loadData } from '../lib/crypto'
import { BronLink } from '../components/BronLink'

interface InsightLink {
  view: NavTarget['view']
  scope: string
  level: NavTarget['level']
  indicatorId?: string
  xId?: string
  yId?: string
  year: number
  label?: string
}
interface ProfileDim {
  dim: string
  label: string
  value: string
  vsRef?: string
}
interface Insight {
  title: string
  persona: string
  profile: ProfileDim[]
  finding: string
  method: string
  why: string
  confidence: 'hoog' | 'middel' | 'laag'
  links: InsightLink[]
}
interface Activity {
  activity: string
  activityId: string
  insights: Insight[]
  assumptions: string[]
}
interface InsightsDoc {
  generated: string
  method?: string
  activities: Activity[]
}

const VIEW_LABEL: Record<string, string> = {
  overzicht: 'Overzicht', kaart: 'Kaart', trends: 'Ontwikkeling',
  gentrificatie: 'Gentrificatie', samenhang: 'Samenhang',
}

export function Inzichten({ ds, state }: { ds: Dataset; state: AppState }) {
  const [doc, setDoc] = useState<InsightsDoc | null>(null)
  const [err, setErr] = useState(false)
  const [active, setActive] = useState<string | null>(null)

  useEffect(() => {
    loadData<InsightsDoc>('./data/insights.json')
      .then((d) => {
        setDoc(d)
        setActive(d.activities[0]?.activityId ?? null)
      })
      .catch(() => setErr(true))
  }, [])

  if (err) return <p className="view-sub">Kon de inzichten niet laden (insights.json ontbreekt).</p>
  if (!doc) return <div className="loading">Inzichten laden…</div>

  const act = doc.activities.find((a) => a.activityId === active) ?? doc.activities[0]

  const scopeLabel = (l: InsightLink) => (l.scope ? regionName(ds, l.scope) : regionName(ds, ds.meta.gemeente))
  const linkLabel = (l: InsightLink) => {
    if (l.label) return l.label
    const lvl = l.level === 'buurt' ? 'buurten' : l.level === 'gebied' ? 'gebieden' : l.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'
    if (l.view === 'samenhang' && l.xId && l.yId) {
      const x = indicatorById(ds, l.xId)?.shortLabel ?? l.xId
      const y = indicatorById(ds, l.yId)?.shortLabel ?? l.yId
      return `${VIEW_LABEL[l.view]}: ${x} × ${y} · ${scopeLabel(l)}, ${lvl}, ${l.year}`
    }
    const ind = l.indicatorId ? indicatorById(ds, l.indicatorId)?.shortLabel ?? l.indicatorId : ''
    return `${VIEW_LABEL[l.view]}${ind ? `: ${ind}` : ''} · ${scopeLabel(l)}, ${lvl}, ${l.year}`
  }

  const go = (l: InsightLink) =>
    state.navigate({
      view: l.view, gm: 'GM0363', scope: l.scope, level: l.level,
      indicatorId: l.indicatorId || undefined, xId: l.xId || undefined, yId: l.yId || undefined,
      year: l.year,
    })

  return (
    <>
      <h1 className="view-title">Doelgroepdossiers voor Dynamo</h1>
      <p className="view-sub">
        Per Dynamo-activiteit een verdiepend onderzoek: precies gedefinieerde doelgroepen, hun
        meer-dimensionale sociaal-demografische profiel, en de multivariate koppeling aan zorg-,
        welzijns- en gezondheidsuitkomsten (regressie, buurttypologie, composietindex, partiële
        correlatie — op buurtniveau). Elk dossier linkt naar de onderliggende analyse.
        Automatisch gegenereerde analyse (taalmodel op basis van de databundel), niet het werk van
        een menselijk expertteam — lees als onderbouwd startpunt, niet als vastgesteld feit.
      </p>
      <div className="notice" role="note">
        ⚠ <strong>Statistisch voorbehoud.</strong> De predictoren hierachter zijn zwaar collineair;
        gestandaardiseerde beta&apos;s zijn <strong>geen</strong> onafhankelijke, causale "drivers" —
        zonder standaardfouten/p-waarden en met tekenomkeringen door collineariteit als artefact.
        RIVM-uitkomsten zijn bovendien deels gemodelleerd uit dezelfde socio-demografie die hier als
        voorspeller dient, wat de hoge R² (circulariteit) deels verklaart. Lees elk verband als
        ecologische samenhang, niet als bewezen oorzaak.
      </div>

      <div className="chip-row" role="group" aria-label="Kies een Dynamo-activiteit">
        {doc.activities.map((a) => (
          <button
            key={a.activityId}
            aria-pressed={a.activityId === act.activityId}
            className={`chip${a.activityId === act.activityId ? ' active' : ''}`}
            onClick={() => setActive(a.activityId)}
          >
            {a.activity}
          </button>
        ))}
      </div>

      <div className="insight-grid wide">
        {act.insights.map((ins, i) => (
          <div key={i} className="insight-card">
            <div className="insight-head">
              <span className={`conf conf-${ins.confidence}`} title={`vertrouwen: ${ins.confidence}`}>
                {ins.confidence}
              </span>
              <h3 className="insight-title">{ins.title}</h3>
            </div>

            <p className="insight-persona"><strong>Doelgroep:</strong> {ins.persona}</p>

            {ins.profile?.length > 0 && (
              <div className="profile-chips" aria-label="Profiel">
                {ins.profile.map((p, k) => (
                  <span key={k} className="profile-chip" title={p.label + (p.vsRef ? ` — ${p.vsRef}` : '')}>
                    <span className="pc-label">{p.label}</span>
                    <span className="pc-value">{p.value}</span>
                  </span>
                ))}
              </div>
            )}

            <p className="insight-finding">{ins.finding}</p>
            <p className="insight-why"><strong>Voor Dynamo:</strong> {ins.why}</p>

            <details className="insight-evidence">
              <summary>Methode &amp; onderbouwing</summary>
              <p>{ins.method}</p>
            </details>

            <div className="insight-links">
              {ins.links.map((l, k) => (
                <button key={k} className="insight-link" onClick={() => go(l)}>
                  → {linkLabel(l)}
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>

      {act.assumptions?.length > 0 && (
        <div className="card" style={{ marginTop: 16 }}>
          <h3 className="card-title">Aannames &amp; methodologische kanttekeningen</h3>
          <ul className="prose" style={{ margin: 0 }}>
            {act.assumptions.map((a, i) => (
              <li key={i} style={{ fontSize: 13 }}>{a}</li>
            ))}
          </ul>
        </div>
      )}

      <p className="view-sub" style={{ marginTop: 16 }}>
        Gegenereerd {doc.generated}. De analyses zijn <strong>ecologisch</strong> (buurtprofielen, geen
        individuen) en deels gebaseerd op gemodelleerde{' '}
        <BronLink state={state} id="rivm-gezondheid">RIVM-schattingen</BronLink>; verbanden zijn
        samenhang, geen causaliteit. Gebruik als onderbouwd startpunt voor locatie- en
        programmakeuzes. Alle databronnen: tabblad <BronLink state={state}>Bronnen</BronLink>.
      </p>
    </>
  )
}
