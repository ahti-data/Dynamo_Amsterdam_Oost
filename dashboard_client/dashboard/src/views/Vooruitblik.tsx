import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, GeoSet } from '../App'
import { StatTile } from '../components/StatTile'
import { BarChart, type BarRow } from '../components/BarChart'
import { Choropleth } from '../components/Choropleth'
import { ForecastChart, type ForecastSeries } from '../components/ForecastChart'
import { SegmentedPicker } from '../components/SegmentedPicker'
import { TabFootnote } from '../components/TabFootnote'
import { areas, regionName, coverageBreakYears, indicatorById } from '../lib/data'
import { fmtValue, fmtDelta } from '../lib/format'
import { forecastArea, forecastGroup, pctChange, absChange, HORIZONS } from '../lib/forecast'

/** Dynamo-doelgroepen: CBS-indicator gekoppeld aan de dienst die erop stuurt. */
interface TargetGroup {
  id: string
  label: string
  short: string
  service: string
  color: string
}
const GROUPS: TargetGroup[] = [
  { id: 'a_65_oo', label: 'Ouderen (65-plus)', short: '65-plus', service: 'Ouderenwerk, seniorenactiviteiten, welzijn op recept', color: 'var(--series-3)' },
  { id: 'a_00_14', label: 'Kinderen (0–14 jaar)', short: '0–14 jr', service: 'Kinderwerk en jeugdwerk', color: 'var(--series-1)' },
  { id: 'a_15_24', label: 'Jongeren (15–24 jaar)', short: '15–24 jr', service: 'Jongerenwerk en talentontwikkeling', color: 'var(--series-2)' },
  { id: 'a_1p_hh', label: 'Alleenwonenden', short: 'alleenwonend', service: 'Buurtwerk en eenzaamheidsbestrijding', color: 'var(--series-5)' },
  { id: 'a_45_64', label: 'Aankomende senioren (45–64 jr)', short: '45–64 jr', service: 'Mantelzorg en voorbereiding op vergrijzing', color: 'var(--series-8)' },
  { id: 'a_hh', label: 'Huishoudens', short: 'huishoudens', service: 'Buurtwerk, Huizen van de Wijk, wonen', color: 'var(--series-6)' },
  { id: 'a_inw', label: 'Totaal inwoners', short: 'inwoners', service: 'Draagvlak en schaal van alle voorzieningen', color: 'var(--series-4)' },
]
/** Leeftijdsbanden voor de opbouw-verschuiving (som + residu 25–44). */
const AGE_BANDS = [
  { id: 'a_00_14', label: '0–14', color: 'var(--series-1)' },
  { id: 'a_15_24', label: '15–24', color: 'var(--series-2)' },
  { id: '__mid', label: '25–44', color: 'var(--series-7)' },
  { id: 'a_45_64', label: '45–64', color: 'var(--series-8)' },
  { id: 'a_65_oo', label: '65+', color: 'var(--series-3)' },
]

export function Vooruitblik({ ds, geo, state }: { ds: Dataset; geo: GeoSet; state: AppState }) {
  const [groupId, setGroupId] = useState('a_65_oo')
  const [horizon, setHorizon] = useState<number>(HORIZONS[HORIZONS.length - 1])
  const [hoverCode, setHoverCode] = useState<string | null>(null)
  const group = GROUPS.find((g) => g.id === groupId) ?? GROUPS[0]
  // dezelfde 9 thema's als Overzicht/Kaart/Tabel — expliciete brug tussen de
  // doelgroep-indeling hier en de thema-indeling elders (MECE-cleanup)
  const groupThemeId = indicatorById(ds, group.id)?.theme
  const groupTheme = groupThemeId ? ds.themes.find((t) => t.id === groupThemeId) : undefined

  const focusCode = state.scope || ds.meta.gemeente
  const focusName = regionName(ds, focusCode)
  const lastYear = ds.years[ds.years.length - 1]
  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])
  const levelNaam =
    state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : state.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'

  // fan chart: alleen het focusgebied met band — een absolute referentielijn van
  // de hele gemeente (veel groter) zou de as platdrukken; de ruimtelijke
  // vergelijking loopt via de ranking en de kaart hieronder.
  const focusFc = useMemo(() => forecastArea(ds, group.id, focusCode), [ds, group.id, focusCode])
  const chartSeries: ForecastSeries[] = useMemo(() => {
    const s: ForecastSeries[] = []
    if (focusFc) s.push({ id: focusCode, label: focusName, color: group.color, points: focusFc.points, showBand: true })
    return s
  }, [focusFc, focusCode, focusName, group.color])

  // prognose per gebied binnen de scope, top-down gerakt naar het focusgebied
  const areaFc = useMemo(
    () => forecastGroup(ds, group.id, list, focusCode),
    [ds, group.id, list, focusCode],
  )

  const ranking: BarRow[] = useMemo(() => {
    const rows = list
      .map((a) => {
        const f = areaFc.get(a.code)
        return { code: a.code, label: a.name, value: f ? pctChange(f, horizon) : null, highlight: state.selectedArea === a.code }
      })
      .filter((r) => r.value != null)
    rows.sort((x, y) => (y.value ?? 0) - (x.value ?? 0))
    // toon de sterkste stijgers en dalers (uiteinden), max 18
    if (rows.length <= 18) return rows
    return [...rows.slice(0, 12), ...rows.slice(-6)]
  }, [list, areaFc, horizon, state.selectedArea])

  // wijken waarvan de trend boven het plafond lag en glad gecomprimeerd is: hun
  // prognose is een getemde ondergrens (nieuwbouw/aanwas groeit sneller dan het
  // model extrapoleert) — meld dit zodat de cijfers niet als exacte waarde ogen
  const compressedShown = useMemo(
    () => ranking.filter((r) => areaFc.get(r.code)?.compressed).map((r) => r.label),
    [ranking, areaFc],
  )

  const mapValues = useMemo(() => {
    const o: Record<string, number | null> = {}
    for (const a of list) {
      const f = areaFc.get(a.code)
      o[a.code] = f ? pctChange(f, horizon) : null
    }
    return o
  }, [list, areaFc, horizon])

  const mapGeo = useMemo(() => {
    const g = state.level === 'buurt' ? geo.buurt : state.level === 'gebied' ? geo.gebied : geo.wijk
    if (!g || state.level === 'stadsdeel') return null
    const codes = new Set(list.map((a) => a.code))
    return { ...g, features: g.features.filter((f) => codes.has(f.properties.code)) }
  }, [geo, state.level, list])

  // leeftijdsopbouw-verschuiving voor het focusgebied (2025 → horizon), incl. residu 25–44
  const ageShift = useMemo(() => {
    const totNow = forecastArea(ds, 'a_inw', focusCode)
    const bands = AGE_BANDS.map((b) => {
      if (b.id === '__mid') return { ...b, now: 0, then: 0 }
      const f = forecastArea(ds, b.id, focusCode)
      return { ...b, now: f?.lastObsValue ?? 0, then: f?.projected[horizon] ?? 0 }
    })
    // residu 25–44 = totaal − overige banden (plausibiliteit: nooit negatief)
    const sumNow = bands.reduce((s, b) => s + (b.id === '__mid' ? 0 : b.now), 0)
    const sumThen = bands.reduce((s, b) => s + (b.id === '__mid' ? 0 : b.then), 0)
    const mid = bands.find((b) => b.id === '__mid')!
    mid.now = Math.max(0, (totNow?.lastObsValue ?? sumNow) - sumNow)
    mid.then = Math.max(0, (totNow?.projected[horizon] ?? sumThen) - sumThen)
    const tNow = bands.reduce((s, b) => s + b.now, 0) || 1
    const tThen = bands.reduce((s, b) => s + b.then, 0) || 1
    return { bands, tNow, tThen }
  }, [ds, focusCode, horizon])

  // conclusies: procentuele verandering per kernaandeelgroep voor het focusgebied
  const focusChanges = useMemo(() => {
    return GROUPS.map((g) => {
      const f = forecastArea(ds, g.id, focusCode)
      return { g, pct: f ? pctChange(f, horizon) : null, abs: f ? absChange(f, horizon) : null }
    })
  }, [ds, focusCode, horizon])

  // koploper-gebied voor de geselecteerde doelgroep
  const topMover = ranking[0]
  const focusPct = focusFc ? pctChange(focusFc, horizon) : null
  const focusAbs = focusFc ? absChange(focusFc, horizon) : null
  const period = `${lastYear}–${horizon}`
  const hasData = !!focusFc && focusFc.lastObsValue > 0
  // dekkingsbreuk (H1): een herindeling die naamkoppeling breekt geeft een
  // nepsprong in de reeks die de trendextrapolatie dan doortrekt
  const coverageBreaks = coverageBreakYears(ds, focusCode)

  return (
    <>
      <h1 className="view-title">Vooruitblik {period}</h1>
      <p className="view-sub">
        Trendprognose van de omvang van Dynamo-doelgroepen per {levelNaam}, op basis van de reeks{' '}
        {ds.years[0]}–{lastYear}. De sociaal-demograaf van het team gebruikt log-lineaire extrapolatie met
        shrinkage naar het bovenliggende gebied, gedempte groei en top-down consistentie. Prognoses zijn{' '}
        <strong>indicatief</strong> en verbreden richting {horizon} — zie de onzekerheidsband en de Verantwoording.
      </p>

      {/* doelgroep-keuze, gekoppeld aan Dynamo-dienst. Geen role="tablist"/"tab":
          er is geen bijbehorend tabpanel-DOM, dus dat vereist roving tabindex +
          aria-controls die er niet is (A11Y-5-regressie) — dit is een filter,
          geen tab-widget, dus role="group" met aria-pressed past beter. */}
      <SegmentedPicker
        ariaLabel="Doelgroep"
        value={group.id}
        options={GROUPS.map((g) => ({ id: g.id, label: g.label }))}
        onChange={(id) => { setGroupId(id); state.setSelectedArea(null) }}
      />
      <p className="view-sub" style={{ marginTop: -8 }}>
        <strong>{group.label}</strong> · stuurt op: {group.service.toLowerCase()}
        {groupTheme && (
          <>
            {' · '}
            <button
              type="button"
              className="bron-link"
              onClick={() =>
                state.navigate({
                  view: 'overzicht',
                  scope: state.scope,
                  level: state.level,
                  indicatorId: groupTheme.headline[0] ?? groupTheme.indicatorIds[0],
                  year: state.year,
                })
              }
            >
              zelfde thema in Overzicht: {groupTheme.title} →
            </button>
          </>
        )}
        <span style={{ marginLeft: 14 }}>
          <span className="seg" role="group" aria-label="Horizon" style={{ display: 'inline-flex', verticalAlign: 'middle' }}>
            {HORIZONS.map((h) => (
              <button key={h} className={horizon === h ? 'active' : ''} onClick={() => setHorizon(h)}>
                {h}
              </button>
            ))}
          </span>
        </span>
      </p>

      {!hasData ? (
        <div className="empty-state">
          <p>
            Onvoldoende reeks om <strong>{group.label}</strong> voor {focusName} te prognosticeren.
          </p>
          {state.level === 'buurt' && (
            <button className="control" style={{ backgroundImage: 'none' }} onClick={() => state.setLevel('wijk')}>
              Bekijk op wijkniveau
            </button>
          )}
        </div>
      ) : (
        <>
          {coverageBreaks.length > 0 && (
            <p className="notice" role="note">
              ⚠ De reeks van {focusName} bevat een dekkingsbreuk rond {coverageBreaks.join(', ')} (een
              herindeling waarbij het aantal meetellende wijken sprong). De trend vóór dat jaar is
              hierdoor niet vergelijkbaar met erna, en de prognose extrapoleert mogelijk die nepsprong
              mee — zie Verantwoording.
            </p>
          )}
          <div className="tile-row">
            <StatTile label={`${group.short} · ${focusName} (${lastYear})`} value={focusFc!.lastObsValue} unit="aantal" trend={focusFc!.history} />
            <StatTile label={`Prognose 2030`} value={focusFc!.projected[2030] ?? null} unit="aantal" />
            <StatTile label={`Prognose ${horizon}`} value={focusFc!.projected[horizon] ?? null} unit="aantal" />
            <StatTile
              label={`Verandering ${period}`}
              value={focusPct}
              unit="pct"
              delta={focusAbs}
              deltaUnit="aantal"
              deltaLabel="personen"
              neutralDelta
            />
          </div>

          <div className="card">
            <h3 className="card-title">{group.label} — waarneming en prognose · {focusName}</h3>
            <p className="card-sub">
              Volle lijn = waarneming ({ds.years[0]}–{lastYear}); stippel + band = prognose (±68% aannemelijke marge).
              De band verbreedt met de horizon: verder vooruit is onzekerder.
            </p>
            <ForecastChart series={chartSeries} lastObsYear={lastYear} height={340} />
          </div>

          <div className="card">
            <div className="card-head">
              <div>
                <h3 className="card-title">Waar groeit of krimpt {group.short}? · {period}</h3>
                <p className="card-sub">
                  Verwachte procentuele verandering per {levelNaam} binnen {focusName}
                  {ranking.length < list.length ? ` (sterkste stijgers en dalers, ${ranking.length} van ${list.length})` : ''}.
                  Staven gesorteerd van meeste groei naar meeste krimp; de kaart kleurt blauw (krimp) tot rood (groei).
                  {compressedShown.length > 0 && (
                    <>
                      {' '}
                      <strong>Let op:</strong> {compressedShown.join(', ')}{' '}
                      {compressedShown.length === 1 ? 'groeit' : 'groeien'} sneller dan het model
                      betrouwbaar extrapoleert (nieuwbouw/aanwas); de trend is afgevlakt naar het
                      plafond, dus deze prognose is een <em>getemde ondergrens</em>.
                    </>
                  )}
                </p>
              </div>
            </div>
            <div className="grid-map">
              <BarChart
                rows={ranking}
                unit="pct"
                color="var(--series-6)"
                onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
                onHover={setHoverCode}
                hovered={hoverCode}
              />
              {mapGeo && mapGeo.features.length > 0 ? (
                <Choropleth
                  geo={mapGeo}
                  values={mapValues}
                  unit="pct"
                  mode="div"
                  height={330}
                  selected={state.selectedArea}
                  onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
                  labelFor={(c) => regionName(ds, c)}
                  hovered={hoverCode}
                  onHover={setHoverCode}
                  ariaLabel={`Kaart: verwachte verandering ${group.label}, ${period}`}
                  divLabels={{ low: 'krimp', high: 'groei' }}
                />
              ) : (
                <p className="view-sub">Geen kaart op dit niveau — kies wijk of buurt.</p>
              )}
            </div>
          </div>

          <div className="grid-2">
            <div className="card">
              <h3 className="card-title">Leeftijdsopbouw verschuift · {focusName}</h3>
              <p className="card-sub">
                Verwachte samenstelling {lastYear} versus {horizon}. De 25–44-groep is afgeleid als restpost
                (totaal − overige klassen).
              </p>
              <AgeShiftBars ageShift={ageShift} lastYear={lastYear} horizon={horizon} />
            </div>

            <div className="card">
              <h3 className="card-title">Conclusies voor de programmering</h3>
              <p className="card-sub">Automatisch afgeleid uit de prognose voor {focusName} · {period}.</p>
              <ul className="conclusion-list">
                {focusChanges
                  .filter((c) => c.pct != null)
                  .sort((a, b) => Math.abs(b.pct!) - Math.abs(a.pct!))
                  .slice(0, 5)
                  .map(({ g, pct, abs }) => (
                    <li key={g.id}>
                      <span
                        className="conclusion-dot"
                        style={{ background: pct! >= 3 ? 'var(--div-pos-2)' : pct! <= -3 ? 'var(--div-neg-2)' : 'var(--text-muted)' }}
                      />
                      <span>
                        <strong>{g.label}:</strong> {pct! >= 0 ? 'groeit' : 'krimpt'} naar verwachting met{' '}
                        <strong>{fmtValue(Math.abs(pct!), 'pct')}</strong> ({fmtDelta(abs, 'aantal')} personen) tot {horizon}.{' '}
                        {conclusionAdvice(g.id, pct!)}
                      </span>
                    </li>
                  ))}
                {topMover && topMover.value != null && (
                  <li>
                    <span className="conclusion-dot" style={{ background: 'var(--brand)' }} />
                    <span>
                      Sterkste beweging voor {group.short} binnen {focusName}:{' '}
                      <strong>{topMover.label}</strong> ({fmtValue(topMover.value, 'pct')} tot {horizon}) —{' '}
                      overweeg hier als eerste te herprogrammeren.
                    </span>
                  </li>
                )}
              </ul>
            </div>
          </div>

          <p className="notice" role="note">
            ⚠ <strong>Voorbehoud.</strong> Dit is een trenddoortrekking, geen bevolkingsprognose van CBS/PBL of Primos.
            Er zijn geen geplande nieuwbouw, sloop of beleidswijzigingen meegenomen. Buurtcijfers zijn klein en ruizig;
            de betrouwbaarheid neemt af naar {horizon} en op fijner niveau. Cijfers zijn gebiedsgemiddelden (ecologisch
            voorbehoud). Zie <em>Verantwoording → Vooruitblik</em> voor de volledige methode en aannames.
          </p>
        </>
      )}

      <TabFootnote viewId="vooruitblik" ds={ds} state={state} />
    </>
  )
}

/** Dienstgericht advies per doelgroep, afhankelijk van de richting van de trend. */
function conclusionAdvice(id: string, pct: number): string {
  const up = pct >= 3
  const down = pct <= -3
  switch (id) {
    case 'a_65_oo':
      return up ? 'Schaal ouderenwerk en eenzaamheidsaanpak op.' : down ? 'Ruimte om ouderencapaciteit te verschuiven.' : 'Houd ouderenwerk op peil.'
    case 'a_00_14':
      return up ? 'Versterk kinderwerk en gezinsondersteuning.' : down ? 'Kinderwerk kan krimpen of gebundeld worden.' : 'Kinderwerk stabiel.'
    case 'a_15_24':
      return up ? 'Investeer in jongerenwerk en talentontwikkeling.' : down ? 'Jongerenwerk gerichter inzetten.' : 'Jongerenwerk stabiel.'
    case 'a_1p_hh':
      return up ? 'Sterker eenzaamheidssignaal — meer ontmoeting in de buurt.' : down ? 'Iets minder druk op ontmoetingsaanbod.' : 'Ontmoetingsaanbod op peil.'
    case 'a_45_64':
      return up ? 'Anticipeer op toekomstige vergrijzing en mantelzorgvraag.' : down ? 'Minder aankomende senioren.' : 'Stabiele middengroep.'
    case 'a_hh':
      return up ? 'Groeiende voorzieningendruk in de buurt.' : down ? 'Afnemende huishoudensdruk.' : 'Stabiel aantal huishoudens.'
    default:
      return up ? 'Groeiend draagvlak voor voorzieningen.' : down ? 'Krimpend draagvlak — heroverweeg schaal.' : 'Stabiel inwonertal.'
  }
}

/** Twee 100%-gestapelde balken (nu vs. horizon) die de leeftijdsverschuiving tonen. */
function AgeShiftBars({
  ageShift,
  lastYear,
  horizon,
}: {
  ageShift: { bands: { id: string; label: string; color: string; now: number; then: number }[]; tNow: number; tThen: number }
  lastYear: number
  horizon: number
}) {
  const { bands, tNow, tThen } = ageShift
  const bar = (key: 'now' | 'then', total: number, label: string) => (
    <div style={{ marginBottom: 10 }}>
      <div className="viz-axis-text" style={{ marginBottom: 3 }}>
        {label} · {fmtValue(total, 'aantal')} personen
      </div>
      <div style={{ display: 'flex', height: 26, borderRadius: 5, overflow: 'hidden', border: '1px solid var(--border)' }}>
        {bands.map((b) => {
          const share = (b[key] / (total || 1)) * 100
          if (share < 0.5) return null
          return (
            <div
              key={b.id}
              title={`${b.label}: ${fmtValue(b[key], 'aantal')} (${share.toFixed(0)}%)`}
              style={{ width: `${share}%`, background: b.color, display: 'flex', alignItems: 'center', justifyContent: 'center' }}
            >
              {share >= 9 && <span style={{ fontSize: 10, color: '#fff', fontWeight: 600 }}>{share.toFixed(0)}%</span>}
            </div>
          )
        })}
      </div>
    </div>
  )
  return (
    <>
      {bar('now', tNow, `${lastYear} (waarneming)`)}
      {bar('then', tThen, `${horizon} (prognose)`)}
      <div className="legend-row" style={{ marginTop: 6 }}>
        {bands.map((b) => {
          const sNow = (b.now / (tNow || 1)) * 100
          const sThen = (b.then / (tThen || 1)) * 100
          const dpp = sThen - sNow
          return (
            <span key={b.id} className="legend-item">
              <span className="key-line" style={{ background: b.color }} />
              {b.label}
              <span style={{ color: Math.abs(dpp) < 0.3 ? 'var(--text-muted)' : dpp > 0 ? 'var(--delta-up)' : 'var(--delta-down)', marginLeft: 4 }}>
                {dpp >= 0 ? '+' : ''}{dpp.toFixed(1)} pp
              </span>
            </span>
          )
        })}
      </div>
    </>
  )
}
