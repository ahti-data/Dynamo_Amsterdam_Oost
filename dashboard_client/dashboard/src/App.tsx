import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { Dataset, GemeenteIndex, GeoCollection, RegionLevel } from './types'
import { levelsForScope, regionsOf } from './lib/data'
import { detectEncryption, loadData } from './lib/crypto'
import { UnlockGate } from './components/UnlockGate'
import { ErrorBoundary } from './ErrorBoundary'
import { Overzicht } from './views/Overzicht'
import { Kaart } from './views/Kaart'
import { Trends } from './views/Trends'
import { Vooruitblik } from './views/Vooruitblik'
import { Gentrificatie } from './views/Gentrificatie'
import { Samenhang } from './views/Samenhang'
import { Inzichten } from './views/Inzichten'
import { Tabel } from './views/Tabel'
import { Bronnen } from './views/Bronnen'
import { Verantwoording } from './views/Verantwoording'
import dynamoLogo from './assets/dynamo.png'
import ahtiLogo from './assets/ahti.png'

// Volgorde bewust gegroepeerd (i.p.v. de oude vlakke rij) zodat de navigatie
// zelf al laat zien welke tabbladen bij elkaar horen — zie NAV_GROUPS hieronder.
export const VIEWS = [
  { id: 'inzichten', label: 'Inzichten', group: 'Narratief' },
  { id: 'vooruitblik', label: 'Vooruitblik', group: 'Narratief' },
  { id: 'overzicht', label: 'Overzicht', group: 'Verkennen' },
  { id: 'kaart', label: 'Kaart', group: 'Verkennen' },
  { id: 'trends', label: 'Ontwikkeling', group: 'Verkennen' },
  { id: 'tabel', label: 'Tabel', group: 'Verkennen' },
  { id: 'gentrificatie', label: 'Gentrificatie', group: 'Analyse' },
  { id: 'samenhang', label: 'Samenhang', group: 'Analyse' },
  { id: 'verantwoording', label: 'Verantwoording', group: 'Referentie' },
  { id: 'bronnen', label: 'Bronnen', group: 'Referentie' },
] as const

export type ViewId = (typeof VIEWS)[number]['id']

/** VIEWS samengevoegd tot aaneengesloten clusters, voor de navigatiebalk. */
const NAV_GROUPS: { group: string; views: (typeof VIEWS)[number][] }[] = (() => {
  const out: { group: string; views: (typeof VIEWS)[number][] }[] = []
  for (const v of VIEWS) {
    const last = out[out.length - 1]
    if (last && last.group === v.group) last.views.push(v)
    else out.push({ group: v.group, views: [v] })
  }
  return out
})()

export interface GeoSet {
  wijk: GeoCollection | null
  buurt: GeoCollection | null
  gebied: GeoCollection | null
}

export interface AppState {
  year: number
  setYear: (y: number) => void
  themeId: string
  setThemeId: (t: string) => void
  indicatorId: string
  setIndicatorId: (i: string) => void
  selectedArea: string | null
  setSelectedArea: (w: string | null) => void
  /** analyse-scope: '' = hele gemeente, of code van stadsdeel/gebied */
  scope: string
  /** detailniveau van de views */
  level: RegionLevel
  setLevel: (l: RegionLevel) => void
  /** samenhang: voorgeselecteerd X-Y-paar (deep-link vanuit Inzichten) */
  pendingPair: { x: string; y: string } | null
  clearPendingPair: () => void
  /** deep-link vanuit het Inzichten-tabblad naar een analyse */
  navigate: (t: NavTarget) => void
  /** id van de bron die op het Bronnen-tabblad in beeld gescrold moet worden */
  sourceAnchor: string | null
  /** open het Bronnen-tabblad, eventueel direct bij een specifieke dataset */
  openSource: (id?: string) => void
  clearSourceAnchor: () => void
  /** id van de verantwoordingssectie die op dat tabblad in beeld gescrold moet worden */
  verantwoordingAnchor: string | null
  /** open het Verantwoording-tabblad, eventueel direct bij een specifieke sectie */
  openVerantwoording: (id?: string) => void
  clearVerantwoordingAnchor: () => void
}

export interface NavTarget {
  view: 'overzicht' | 'kaart' | 'trends' | 'gentrificatie' | 'samenhang'
  gm?: string
  scope: string
  level: RegionLevel
  indicatorId?: string
  xId?: string
  yId?: string
  year: number
}

const DEFAULT_SCOPE_AMSTERDAM = 'SD-M' // stadsdeel Oost — thuisbasis Dynamo

/* ---------- URL-state: analyse deelbaar en reproduceerbaar (review #13) ---------- */
interface UrlState {
  gm?: string
  view?: ViewId
  scope?: string
  level?: RegionLevel
  theme?: string
  ind?: string
  year?: number
}

function readUrlState(): UrlState {
  const p = new URLSearchParams(window.location.hash.replace(/^#/, ''))
  const s: UrlState = {}
  const gm = p.get('gm')
  if (gm && /^GM\d{4}$/.test(gm)) s.gm = gm
  const view = p.get('view') as ViewId | null
  if (view && VIEWS.some((v) => v.id === view)) s.view = view
  if (p.get('scope') != null) s.scope = p.get('scope')!
  const level = p.get('level') as RegionLevel | null
  if (level && ['stadsdeel', 'gebied', 'wijk', 'buurt'].includes(level)) s.level = level
  if (p.get('theme')) s.theme = p.get('theme')!
  if (p.get('ind')) s.ind = p.get('ind')!
  const year = Number(p.get('year'))
  if (year >= 2000 && year <= 2100) s.year = year
  return s
}

function writeUrlState(s: Required<Omit<UrlState, 'year'>> & { year: number }) {
  const p = new URLSearchParams()
  p.set('gm', s.gm)
  p.set('view', s.view)
  p.set('scope', s.scope) // altijd serialiseren, ook '' (hele gemeente) — anders valt een gedeelde link terug op de default (URL-1)
  p.set('level', s.level)
  p.set('theme', s.theme)
  p.set('ind', s.ind)
  p.set('year', String(s.year))
  history.replaceState(null, '', `#${p.toString()}`)
}

// laadt (en ontsleutelt in encryptie-modus) een databestand
async function fetchJson<T>(url: string, signal?: AbortSignal): Promise<T> {
  return loadData<T>(url, signal)
}

async function fetchGeo(url: string, signal?: AbortSignal): Promise<GeoCollection | null> {
  try {
    return await loadData<GeoCollection>(url, signal)
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e
    return null // ontbrekende/optionele geometrie: vlak blijft leeg
  }
}

export default function App() {
  const initial = useRef(readUrlState())
  const [index, setIndex] = useState<GemeenteIndex | null>(null)
  const [gm, setGm] = useState<string>('')
  const [ds, setDs] = useState<Dataset | null>(null)
  const [geo, setGeo] = useState<GeoSet>({ wijk: null, buurt: null, gebied: null })
  const [error, setError] = useState<string | null>(null)
  const [retry, setRetry] = useState(0)
  // encryptie-modus: laad pas data als de build ongesleuteld is (plain) of na
  // ontgrendeling. `locked` toont het wachtwoordscherm.
  const [ready, setReady] = useState(false)
  const [locked, setLocked] = useState(false)
  const [view, setView] = useState<ViewId>(initial.current.view ?? 'inzichten')
  const [dark, setDark] = useState(
    () => window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false,
  )

  const [year, setYear] = useState(initial.current.year ?? 0)
  const [themeId, setThemeId] = useState('')
  const [indicatorId, setIndicatorId] = useState('')
  const [selectedArea, setSelectedArea] = useState<string | null>(null)
  const [scope, setScope] = useState('')
  const [level, setLevel] = useState<RegionLevel>(initial.current.level ?? 'wijk')
  const [pendingPair, setPendingPair] = useState<{ x: string; y: string } | null>(null)
  const [sourceAnchor, setSourceAnchor] = useState<string | null>(null)
  const [verantwoordingAnchor, setVerantwoordingAnchor] = useState<string | null>(null)
  const pendingNav = useRef<NavTarget | null>(null)

  useEffect(() => {
    document.documentElement.dataset.theme = dark ? 'dark' : 'light'
  }, [dark])

  // detecteer of de build versleuteld is; zo niet, meteen laden
  useEffect(() => {
    detectEncryption().then((m) => (m === 'plain' ? setReady(true) : setLocked(true)))
  }, [])

  // index laden, dan gemeente uit URL of default
  useEffect(() => {
    if (!ready) return
    setError(null)
    fetchJson<GemeenteIndex>('./data/index.json')
      .then((idx) => {
        setIndex(idx)
        const wanted = initial.current.gm
        setGm(wanted && idx.gemeenten.some((g) => g.code === wanted) ? wanted : idx.default)
      })
      .catch((e: Error) => setError(e.message))
  }, [retry, ready])

  // gemeentebundel + geometrieën laden; oude fetches afbreken (review #23)
  useEffect(() => {
    if (!ready || !gm) return
    const ctrl = new AbortController()
    setDs(null)
    setError(null)
    Promise.all([
      fetchJson<Dataset>(`./data/gm/${gm}.json`, ctrl.signal),
      fetchGeo(`./data/gm/${gm}_wijken.geojson`, ctrl.signal),
      fetchGeo(`./data/gm/${gm}_buurten.geojson`, ctrl.signal),
      fetchGeo(`./data/gm/${gm}_gebieden.geojson`, ctrl.signal),
    ])
      .then(([d, gw, gb, gg]) => {
        setDs(d)
        setGeo({ wijk: gw, buurt: gb, gebied: gg })
        // deep-link vanuit Inzichten dat een gemeentewissel triggerde: pas ná de
        // load het volledige NavTarget toe i.p.v. de defaults (NAV-2)
        const nav = pendingNav.current
        if (nav && nav.gm === gm) {
          pendingNav.current = null
          setYear(d.years.includes(nav.year) ? nav.year : d.years[d.years.length - 1])
          if (nav.indicatorId && d.indicators.some((x) => x.id === nav.indicatorId)) {
            setIndicatorId(nav.indicatorId)
            const th = d.indicators.find((x) => x.id === nav.indicatorId)?.theme
            if (th) setThemeId(th)
          }
          setScope(d.regions.some((r) => r.code === nav.scope) || nav.scope === '' ? nav.scope : '')
          setLevel(nav.level)
          setPendingPair(nav.xId && nav.yId ? { x: nav.xId, y: nav.yId } : null)
          setSelectedArea(null)
          return
        }
        setYear((y) => (y && d.years.includes(y) ? y : d.years[d.years.length - 1]))
        const uTheme = initial.current.theme
        const uInd = initial.current.ind
        setThemeId((t) => {
          const cand = uTheme && d.themes.some((x) => x.id === uTheme) ? uTheme : t
          return d.themes.some((x) => x.id === cand) ? cand : d.themes[0].id
        })
        setIndicatorId((i) => {
          const cand = uInd && d.indicators.some((x) => x.id === uInd) ? uInd : i
          return d.indicators.some((x) => x.id === cand)
            ? cand
            : d.themes[0]?.headline[0] ?? d.themes[0]?.indicatorIds[0] ?? ''
        })
        const uScope = initial.current.scope
        const scopeOk = uScope != null && (uScope === '' || d.regions.some((r) => r.code === uScope))
        setScope(scopeOk ? uScope! : gm === 'GM0363' ? DEFAULT_SCOPE_AMSTERDAM : '')
        initial.current = {} // URL-state alleen bij eerste load toepassen
        setSelectedArea(null)
      })
      .catch((e: Error) => {
        if (e.name !== 'AbortError') setError(e.message)
      })
    return () => ctrl.abort()
  }, [gm, retry, ready])

  // huidige selectie in de URL bewaren zodat een analyse deelbaar is
  useEffect(() => {
    if (!ds) return
    writeUrlState({ gm, view, scope, level, theme: themeId, ind: indicatorId, year })
  }, [ds, gm, view, scope, level, themeId, indicatorId, year])

  const changeScope = useCallback(
    (s: string) => {
      setScope(s)
      setSelectedArea(null)
      if (!ds) return
      const lvls = levelsForScope(ds, s)
      setLevel((lv) => (lvls.includes(lv) ? lv : lvls.includes('wijk') ? 'wijk' : lvls[0]))
    },
    [ds],
  )

  // deep-link vanuit Inzichten: zet de hele analysecontext in één keer
  const navigate = useCallback(
    (t: NavTarget) => {
      setView(t.view)
      window.scrollTo(0, 0)
      if (t.gm && t.gm !== gm) {
        // gemeentewissel: laat de load-.then() het NavTarget toepassen (NAV-2)
        pendingNav.current = t
        setGm(t.gm)
        return
      }
      setScope(t.scope)
      setLevel(t.level)
      setYear(t.year)
      setSelectedArea(null)
      if (t.indicatorId && ds) {
        setIndicatorId(t.indicatorId)
        const th = ds.indicators.find((i) => i.id === t.indicatorId)?.theme
        if (th) setThemeId(th)
      }
      setPendingPair(t.xId && t.yId ? { x: t.xId, y: t.yId } : null)
    },
    [ds, gm],
  )

  // deep-link naar een bron: open het Bronnen-tabblad bij de betreffende dataset
  const openSource = useCallback((id?: string) => {
    setSourceAnchor(id ?? null)
    setView('bronnen')
    window.scrollTo(0, 0)
  }, [])

  // deep-link naar de verantwoording: open dat tabblad bij de betreffende sectie
  const openVerantwoording = useCallback((id?: string) => {
    setVerantwoordingAnchor(id ?? null)
    setView('verantwoording')
    window.scrollTo(0, 0)
  }, [])

  const state: AppState = useMemo(
    () => ({
      year, setYear, themeId, setThemeId, indicatorId, setIndicatorId,
      selectedArea, setSelectedArea, scope, level, setLevel,
      pendingPair, clearPendingPair: () => setPendingPair(null), navigate,
      sourceAnchor, openSource, clearSourceAnchor: () => setSourceAnchor(null),
      verantwoordingAnchor, openVerantwoording,
      clearVerantwoordingAnchor: () => setVerantwoordingAnchor(null),
    }),
    [
      year, themeId, indicatorId, selectedArea, scope, level, pendingPair, navigate,
      sourceAnchor, openSource, verantwoordingAnchor, openVerantwoording,
    ],
  )

  if (locked)
    return <UnlockGate onUnlocked={() => { setLocked(false); setReady(true) }} />
  if (error)
    return (
      <div className="loading" role="alert">
        <div style={{ textAlign: 'center' }}>
          <p>
            Kon de data niet laden ({error}). Controleer of <code>data-prep/build_data.py</code> is
            gedraaid.
          </p>
          <button className="control" style={{ backgroundImage: 'none' }} onClick={() => setRetry((r) => r + 1)}>
            Opnieuw proberen
          </button>
        </div>
      </div>
    )
  if (!index || !ds) return <div className="loading">Data laden…</div>

  const scopeOptions = [
    ...regionsOf(ds, 'stadsdeel').map((r) => ({ code: r.code, name: r.name, group: 'Stadsdelen & stadsgebied' })),
    ...regionsOf(ds, 'gebied').map((r) => ({
      code: r.code,
      name: r.code === 'GB-westpoort' ? `${r.name} (buiten de 25 GGW-gebieden)` : r.name,
      group: 'GGW-gebieden',
    })),
  ]
  const groups = [...new Set(scopeOptions.map((o) => o.group))]
  const emptyDataset = ds.indicators.length === 0

  return (
    <div className="app">
      <a href="#main" className="skip-link">Naar de inhoud</a>
      <header className="topbar">
        <div className="brand">
          <span className="brand-logos">
            <img src={dynamoLogo} alt="Dynamo — samen in de buurt" className="logo logo-dynamo" />
            <span className="logo-divider" aria-hidden />
            <img src={ahtiLogo} alt="ahti — Amsterdam Health & Technology Institute" className="logo logo-ahti" />
          </span>
          <span className="brand-sub">Demografische monitor</span>
        </div>
        <nav className="nav" aria-label="Hoofdnavigatie">
          {NAV_GROUPS.map((g) => (
            <div key={g.group} className="nav-group" role="group" aria-label={g.group} title={g.group}>
              {g.views.map((v) => (
                <button key={v.id} className={view === v.id ? 'active' : ''} onClick={() => setView(v.id)}>
                  {v.label}
                </button>
              ))}
            </div>
          ))}
          <button
            className="theme-toggle"
            onClick={() => setDark((d) => !d)}
            title={dark ? 'Licht thema' : 'Donker thema'}
            aria-label="Thema wisselen"
          >
            {dark ? '☀' : '☾'}
          </button>
        </nav>
      </header>

      {view !== 'verantwoording' && view !== 'inzichten' && view !== 'bronnen' && (
        <div className="filterbar scopebar">
          <label>Gemeente</label>
          <select className="control" value={gm} onChange={(e) => setGm(e.target.value)} aria-label="Gemeente">
            {[...index.gemeenten]
              .sort((a, b) => a.naam.localeCompare(b.naam, 'nl'))
              .map((g) => (
                <option key={g.code} value={g.code}>
                  {g.naam}
                </option>
              ))}
          </select>

          {scopeOptions.length > 0 && (
            <>
              <label>Focus</label>
              <select
                className="control"
                value={scope}
                onChange={(e) => changeScope(e.target.value)}
                aria-label="Focusgebied"
              >
                <option value="">Hele gemeente</option>
                {groups.map((grp) => (
                  <optgroup key={grp} label={grp}>
                    {scopeOptions
                      .filter((o) => o.group === grp)
                      .map((o) => (
                        <option key={o.code} value={o.code}>
                          {o.name}
                        </option>
                      ))}
                  </optgroup>
                ))}
              </select>
            </>
          )}

          <label>Peiljaar</label>
          <select
            className="control"
            value={year}
            onChange={(e) => setYear(Number(e.target.value))}
            aria-label="Peiljaar"
          >
            {ds.years.map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </select>

          <div className="seg" role="group" aria-label="Niveau">
            {levelsForScope(ds, scope).map((lv) => (
              <button
                key={lv}
                className={level === lv ? 'active' : ''}
                onClick={() => {
                  setLevel(lv)
                  setSelectedArea(null)
                }}
              >
                {lv === 'stadsdeel' ? 'Stadsdelen' : lv === 'gebied' ? 'Gebieden' : lv === 'wijk' ? 'Wijken' : 'Buurten'}
              </button>
            ))}
          </div>
        </div>
      )}

      <main className="main" id="main">
        <ErrorBoundary key={`${view}-${gm}`}>
          {emptyDataset && view !== 'verantwoording' ? (
            <div className="empty-state">
              <p>
                Voor {index.gemeenten.find((g) => g.code === gm)?.naam ?? gm} zijn geen bruikbare
                indicatoren beschikbaar in de huidige databundel.
              </p>
            </div>
          ) : (
            <>
              {view === 'inzichten' && <Inzichten ds={ds} state={state} />}
              {view === 'overzicht' && <Overzicht ds={ds} geo={geo} state={state} />}
              {view === 'kaart' && <Kaart ds={ds} geo={geo} state={state} />}
              {view === 'trends' && <Trends ds={ds} state={state} />}
              {view === 'vooruitblik' && <Vooruitblik ds={ds} geo={geo} state={state} />}
              {view === 'gentrificatie' && <Gentrificatie ds={ds} geo={geo} state={state} />}
              {view === 'samenhang' && <Samenhang ds={ds} geo={geo} state={state} />}
              {view === 'tabel' && <Tabel ds={ds} state={state} />}
              {view === 'bronnen' && <Bronnen state={state} />}
              {view === 'verantwoording' && <Verantwoording ds={ds} state={state} />}
            </>
          )}
        </ErrorBoundary>
      </main>

      <footer className="footer">
        <span>
          Bron:{' '}
          <button type="button" className="bron-link" onClick={() => state.openSource('cbs-kwb')}>
            {ds.meta.source}
          </button>{' '}
          · verslagjaren {ds.meta.yearsCovered.join(', ')} · {index.gemeenten.length} gemeenten (alle
          ≥100.000 inwoners + Amsterdamse buurgemeenten) ·{' '}
          <button type="button" className="bron-link" onClick={() => state.openSource()}>
            alle bronnen
          </button>
        </span>
        <span>Gegenereerd {ds.meta.generated} · Dynamo × ahti · signalerings- en verkenningsinstrument</span>
      </footer>
    </div>
  )
}
