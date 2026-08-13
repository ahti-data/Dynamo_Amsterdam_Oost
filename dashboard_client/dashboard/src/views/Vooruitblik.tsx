import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, GeoSet } from '../App'
import { BarChart, type BarRow } from '../components/BarChart'
import { Choropleth } from '../components/Choropleth'
import { ForecastChart, type ForecastSeries } from '../components/ForecastChart'
import { TabFootnote } from '../components/TabFootnote'
import { areas, regionName, coverageBreakYears } from '../lib/data'
import { forecastArea, forecastGroup, pctChange } from '../lib/forecast'
import { GROUPS } from '../lib/targetGroups'

export function Vooruitblik({ ds, geo, state }: { ds: Dataset; geo: GeoSet; state: AppState }) {
  const [hoverCode, setHoverCode] = useState<string | null>(null)
  const group = GROUPS.find((g) => g.id === state.groupId) ?? GROUPS[0]
  const horizon = state.horizon

  const focusCode = state.scope || ds.meta.gemeente
  const focusName = regionName(ds, focusCode)
  const lastYear = ds.years[ds.years.length - 1]
  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])
  const levelNaam =
    state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : state.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'

  // chart: alleen het focusgebied — een absolute referentielijn van de hele
  // gemeente (veel groter) zou de as platdrukken; de ruimtelijke vergelijking
  // loopt via de ranking en de kaart hieronder.
  const focusFc = useMemo(() => forecastArea(ds, group.id, focusCode), [ds, group.id, focusCode])
  const chartSeries: ForecastSeries[] = useMemo(() => {
    const s: ForecastSeries[] = []
    if (focusFc) s.push({ id: focusCode, label: focusName, color: group.color, points: focusFc.points })
    return s
  }, [focusFc, focusCode, focusName, group.color])
  const hasOfficialForecast = focusFc?.points.some((p) => p.forecast) ?? false

  // officiële prognose per gebied binnen de scope (geen model, alleen O&S/BBGA)
  const areaFc = useMemo(() => forecastGroup(ds, group.id, list), [ds, group.id, list])

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
  // nepsprong in de waargenomen reeks vóór dat jaar
  const coverageBreaks = coverageBreakYears(ds, focusCode)

  return (
    <>
      <h1 className="view-title">Vooruitblik {period}</h1>
      <p className="view-sub view-sub-wide">
        Officiële bevolkingsprognose van gemeente Amsterdam (O&amp;S/BBGA) voor de omvang van Dynamo-doelgroepen,
        uitsluitend waar die bron bestaat. Dekking: totaal inwoners en 65-plus voor heel Amsterdam; kinderen,
        jongeren en 45–64-jarigen alleen voor stadsdeel Oost en zijn wijken. Er is bewust <strong>geen eigen model</strong>{' '}
        als vangnet — waar geen officiële prognose bestaat (buurten, alleenwonenden/huishoudens, andere gemeenten),
        toont deze tool dat expliciet in plaats van een verzonnen getal. Zie de Verantwoording voor de volledige bronnen.
      </p>

      <p className="view-sub" style={{ marginTop: -8 }}>
        <strong>{group.label}</strong> · stuurt op: {group.service.toLowerCase()}
      </p>

      {!hasData ? (
        <div className="empty-state">
          <p>
            Geen historische reeks voor <strong>{group.label}</strong> in {focusName}.
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
              herindeling waarbij het aantal meetellende wijken sprong). De cijfers vóór dat jaar zijn hierdoor
              niet vergelijkbaar met erna — zie Verantwoording.
            </p>
          )}
          <div className="card">
            <h3 className="card-title">{group.label} — waarneming en prognose · {focusName}</h3>
            <p className="card-sub">
              {hasOfficialForecast ? (
                <>
                  Volle lijn = waarneming ({ds.years[0]}–{lastYear}); stippel = officiële bevolkingsprognose
                  (O&amp;S/BBGA, gemeente Amsterdam) voor {focusName}. Geen onzekerheidsband: deze bronnen
                  publiceren geen interval — zie het voorbehoud onderaan.
                </>
              ) : (
                <>
                  Volle lijn = waarneming ({ds.years[0]}–{lastYear}). Voor <strong>{group.label}</strong> in{' '}
                  {focusName} bestaat geen officiële O&amp;S/BBGA-prognose — zie het voorbehoud onderaan voor
                  waar deze bron wel dekking heeft.
                </>
              )}
            </p>
            <ForecastChart series={chartSeries} lastObsYear={lastYear} height={340} />
          </div>

          <div className="card">
            <div className="card-head">
              <div>
                <h3 className="card-title">Waar groeit of krimpt {group.short}? · {period}</h3>
                <p className="card-sub">
                  Verwachte procentuele verandering per {levelNaam} binnen {focusName}, volgens de officiële
                  O&amp;S/BBGA-prognose
                  {ranking.length > 0 && ranking.length < list.length
                    ? ` (${ranking.length} van ${list.length} ${levelNaam} hebben dekking)`
                    : ''}
                  {ranking.length > 0 && '. Staven gesorteerd van meeste groei naar meeste krimp; de kaart kleurt blauw (krimp) tot rood (groei).'}
                </p>
              </div>
            </div>
            {ranking.length === 0 ? (
              <div className="empty-state">
                <p>
                  Geen van de {list.length} {levelNaam} in {focusName} heeft een officiële prognose voor{' '}
                  <strong>{group.label}</strong> in {horizon}.
                </p>
              </div>
            ) : (
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
            )}
          </div>

          <p className="notice" role="note">
            ⚠ <strong>Voorbehoud.</strong> Dit zijn de officiële bevolkingsprognosecijfers van gemeente Amsterdam
            (O&amp;S/BBGA) — geen eigen model. Ze bestaan alleen voor <strong>totaal inwoners</strong> en{' '}
            <strong>65-plus</strong> (heel Amsterdam: gemeente, stadsdeel, gebied en wijk) en voor{' '}
            <strong>kinderen (0–14), jongeren (15–24) en 45–64-jarigen</strong> (alleen stadsdeel Oost en zijn
            wijken). Voor <strong>alleenwonenden en huishoudens</strong>, elke <strong>buurt</strong> en elke{' '}
            <strong>andere gemeente</strong> is er geen officiële bron en dus bewust geen prognose — geen
            verzonnen trendlijn als vangnet. De bronnen publiceren geen onzekerheidsinterval. Cijfers zijn
            gebiedsgemiddelden (ecologisch voorbehoud). Zie <em>Verantwoording → Vooruitblik</em> voor de
            volledige bronnen en aannames.
          </p>
        </>
      )}

      <TabFootnote viewId="vooruitblik" ds={ds} state={state} />
    </>
  )
}
