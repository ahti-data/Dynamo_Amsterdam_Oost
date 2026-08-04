import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, GeoSet } from '../App'
import { BarChart, type BarRow } from '../components/BarChart'
import { Choropleth } from '../components/Choropleth'
import { ForecastChart, type ForecastSeries } from '../components/ForecastChart'
import { TabFootnote } from '../components/TabFootnote'
import { areas, regionName, coverageBreakYears, indicatorById } from '../lib/data'
import { forecastArea, forecastGroup, pctChange, HORIZONS } from '../lib/forecast'

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

  const period = `${lastYear}–${horizon}`
  const hasData = !!focusFc && focusFc.lastObsValue > 0
  // dekkingsbreuk (H1): een herindeling die naamkoppeling breekt geeft een
  // nepsprong in de reeks die de trendextrapolatie dan doortrekt
  const coverageBreaks = coverageBreakYears(ds, focusCode)

  return (
    <>
      <h1 className="view-title">Vooruitblik {period}</h1>
      <p className="view-sub view-sub-wide">
        Trendprognose van de omvang van Dynamo-doelgroepen per {levelNaam}, op basis van de reeks{' '}
        {ds.years[0]}–{lastYear}. De sociaal-demograaf van het team gebruikt log-lineaire extrapolatie met
        shrinkage naar het bovenliggende gebied, gedempte groei en top-down consistentie. Prognoses zijn{' '}
        <strong>indicatief</strong> en verbreden richting {horizon} — zie de onzekerheidsband en de Verantwoording.
      </p>

      <div className="filterbar" style={{ padding: 0, maxWidth: 'none', margin: '0 0 4px' }}>
        <label htmlFor="vooruitblik-doelgroep">Doelgroep</label>
        <select
          id="vooruitblik-doelgroep"
          className="control"
          value={group.id}
          onChange={(e) => { setGroupId(e.target.value); state.setSelectedArea(null) }}
        >
          {GROUPS.map((g) => (
            <option key={g.id} value={g.id}>{g.label}</option>
          ))}
        </select>
      </div>
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
                  view: 'kaart',
                  scope: state.scope,
                  level: state.level,
                  indicatorId: groupTheme.headline[0] ?? groupTheme.indicatorIds[0],
                  year: state.year,
                })
              }
            >
              zelfde thema in Kaart: {groupTheme.title} →
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
