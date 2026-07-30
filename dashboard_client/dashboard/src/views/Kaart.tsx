import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, GeoSet } from '../App'
import { Choropleth } from '../components/Choropleth'
import { BarChart, type BarRow } from '../components/BarChart'
import { areas, availableYears, getValue, indicatorById, regionName, nearestYear, signalSort, noDataReason } from '../lib/data'
import { fmtValue } from '../lib/format'
import { TabFootnote } from '../components/TabFootnote'

type Mode = 'abs' | 'rel'

export function Kaart({ ds, geo, state }: { ds: Dataset; geo: GeoSet; state: AppState }) {
  const [mode, setMode] = useState<Mode>('abs')
  const [refChoice, setRefChoice] = useState<'gemeente' | 'scope'>('gemeente')
  // hover-koppeling tussen kaart en top-ranglijst
  const [hoverCode, setHoverCode] = useState<string | null>(null)

  const indicator = indicatorById(ds, state.indicatorId) ?? ds.indicators[0]
  // absolute aantallen niet indexeren (advies welzijnsspecialist)
  const relAllowed = indicator.unit !== 'aantal'
  const effMode: Mode = relAllowed ? mode : 'abs'

  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])

  // beschikbaarheid per scope × niveau (review #2)
  const availYears = useMemo(
    () => availableYears(ds, list, indicator.id),
    [ds, list, indicator.id],
  )
  const hasLevelData = availYears.length > 0
  const year = nearestYear(availYears, state.year)

  const refCode = refChoice === 'scope' && state.scope ? state.scope : ds.meta.gemeente
  const refName = regionName(ds, refCode)
  const refValue = getValue(ds, refCode, indicator.id, year)

  const mapValues = useMemo(() => {
    const o: Record<string, number | null> = {}
    for (const a of list) {
      const v = getValue(ds, a.code, indicator.id, year)
      o[a.code] =
        effMode === 'rel'
          ? v != null && refValue != null && refValue !== 0
            ? ((v - refValue) / refValue) * 100
            : null
          : v
    }
    return o
  }, [ds, list, indicator.id, year, effMode, refValue])

  // vaste schaal over alle beschikbare jaren zodat kleuren per jaar vergelijkbaar
  // blijven (review #19); alleen zinvol in absolute modus. De bovengrens wordt op het
  // 90e percentiel (over alle jaren+gebieden) gekapt zodat één extreme wijk niet alle
  // andere in de lichtste klasse drukt (M6); Choropleth krijgt dat als vast domein mee
  // (behoudt jaar-vergelijkbaarheid) en toont het "+"-teken via domainCapped.
  const { domain, domainCapped } = useMemo(() => {
    if (effMode === 'rel' || !hasLevelData) return { domain: undefined, domainCapped: false }
    const all: number[] = []
    for (const y of availYears) {
      for (const a of list) {
        const v = getValue(ds, a.code, indicator.id, y)
        if (v != null) all.push(v)
      }
    }
    if (!all.length) return { domain: undefined, domainCapped: false }
    all.sort((a, b) => a - b)
    const min = all[0]
    const rawMax = all[all.length - 1]
    const p90 = all[Math.min(all.length - 1, Math.floor(all.length * 0.9))]
    const max = all.length >= 5 ? Math.max(p90, min + 0.0001) : rawMax
    return { domain: { min, max }, domainCapped: max < rawMax }
  }, [ds, list, indicator.id, availYears, effMode, hasLevelData])

  const topRows: BarRow[] = useMemo(() => {
    // sterkste signaal eerst o.b.v. indicator.direction, ook in relatieve modus (H3):
    // voor "laag = signaal"-indicatoren (bv. inkomen) is de laagste (meest negatieve) afwijking het signaal
    const cmp = signalSort(indicator.direction)
    const r = list
      .map((a) => ({
        code: a.code,
        label: a.name,
        value: mapValues[a.code],
        highlight: state.selectedArea === a.code,
      }))
      .filter((x) => x.value != null)
    r.sort((x, y) => cmp(x.value, y.value))
    return r.slice(0, 12)
  }, [list, mapValues, state.selectedArea, effMode, indicator.direction])

  const mapGeo = useMemo(() => {
    const g = state.level === 'buurt' ? geo.buurt : state.level === 'gebied' ? geo.gebied : geo.wijk
    if (!g || state.level === 'stadsdeel') return null
    const codes = new Set(list.map((a) => a.code))
    return { ...g, features: g.features.filter((f) => codes.has(f.properties.code)) }
  }, [geo, state.level, list])

  const prevYear = [...availYears].reverse().find((y) => y < year)
  const nextYear = availYears.find((y) => y > year)

  const levelNaam = state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : 'wijken'
  const richtingTekst =
    indicator.direction === 'laag'
      ? 'sterkste signaal = laagste waarde (donker op de kaart)'
      : indicator.direction === 'neutraal'
        ? 'neutrale indicator: hoog is niet per se meer behoefte'
        : 'sterkste signaal = hoogste waarde'

  return (
    <>
      <h1 className="view-title">Kaart — waar is het signaal het sterkst?</h1>
      <p className="view-sub">
        Donker = sterkste ondersteuningssignaal ({richtingTekst}). Schakel naar <em>relatief</em> om
        te zien waar een gebied boven of onder het gemiddelde van {refName} zit — dat onderscheidt
        concentratie van omvang.
      </p>

      <div className="filterbar" style={{ padding: '0 0 14px', maxWidth: 'none' }}>
        <label>Indicator</label>
        <select
          className="control"
          value={indicator.id}
          onChange={(e) => state.setIndicatorId(e.target.value)}
          aria-label="Indicator"
        >
          {ds.themes.map((t) => (
            <optgroup key={t.id} label={t.title}>
              {t.indicatorIds.map((iid) => {
                const ind = indicatorById(ds, iid)
                if (!ind) return null
                const ok = availableYears(ds, list, iid).length > 0
                return (
                  <option key={`${t.id}-${iid}`} value={iid} disabled={!ok}>
                    {ind.label}
                    {!ok ? ' — geen data op dit niveau' : ''}
                  </option>
                )
              })}
            </optgroup>
          ))}
        </select>

        <label>Jaar</label>
        <div className="year-step">
          <button
            onClick={() => prevYear != null && state.setYear(prevYear)}
            disabled={prevYear == null}
            aria-label="Vorig jaar"
          >
            ‹
          </button>
          <span className="year-now">{year}</span>
          <button
            onClick={() => nextYear != null && state.setYear(nextYear)}
            disabled={nextYear == null}
            aria-label="Volgend jaar"
          >
            ›
          </button>
        </div>

        <div className="seg" role="group" aria-label="Weergave">
          <button className={effMode === 'abs' ? 'active' : ''} onClick={() => setMode('abs')}>
            Absoluut
          </button>
          <button
            className={effMode === 'rel' ? 'active' : ''}
            onClick={() => relAllowed && setMode('rel')}
            disabled={!relAllowed}
            style={relAllowed ? undefined : { opacity: 0.4, cursor: 'not-allowed' }}
            title={
              relAllowed
                ? undefined
                : 'Niet zinvol voor absolute aantallen — kies een percentage, gemiddelde of dichtheid'
            }
          >
            Relatief
          </button>
        </div>

        {effMode === 'rel' && state.scope && (
          <div className="seg" role="group" aria-label="Referentie">
            <button className={refChoice === 'gemeente' ? 'active' : ''} onClick={() => setRefChoice('gemeente')}>
              t.o.v. {regionName(ds, ds.meta.gemeente)}
            </button>
            <button className={refChoice === 'scope' ? 'active' : ''} onClick={() => setRefChoice('scope')}>
              t.o.v. {regionName(ds, state.scope)}
            </button>
          </div>
        )}
      </div>

      {year !== state.year && hasLevelData && (
        <p className="notice" role="status">
          ⚠ {indicator.shortLabel} is voor {state.year} niet beschikbaar op dit niveau — weergegeven:{' '}
          <strong>{year}</strong> (beschikbaar: {availYears.join(', ')}).
        </p>
      )}

      {!hasLevelData ? (
        <div className="card">
          <div className="empty-state">
            <p>
              Geen betrouwbare {levelNaam}-data voor <strong>{indicator.label}</strong>.
            </p>
            {state.level === 'buurt' && (
              <button className="control" onClick={() => state.setLevel('wijk')} style={{ backgroundImage: 'none' }}>
                Bekijk deze indicator op wijkniveau
              </button>
            )}
          </div>
        </div>
      ) : (
        <div className="grid-map">
          <div className="card">
            <h3 className="card-title">
              {indicator.label} · {year}
              {effMode === 'rel' ? ` · afwijking t.o.v. ${refName}` : ''}
            </h3>
            <p className="card-sub">
              {effMode === 'rel' && refValue != null
                ? `referentiewaarde ${refName}: ${fmtValue(refValue, indicator.unit)}`
                : `${indicator.description} Kleurschaal is vast over ${availYears[0]}–${availYears[availYears.length - 1]}.`}
              {indicator.isOutcome ? ' Gemodelleerde RIVM-schatting, geen directe telling.' : ''}
            </p>
            {mapGeo && mapGeo.features.length > 0 ? (
              <Choropleth
                geo={mapGeo}
                values={mapValues}
                unit={effMode === 'rel' ? 'pct' : indicator.unit}
                mode={effMode === 'rel' ? 'div' : 'seq'}
                invert={effMode === 'abs' && indicator.direction === 'laag'}
                domain={domain}
                capped={domainCapped}
                height={470}
                selected={state.selectedArea}
                onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
                labelFor={(c) => regionName(ds, c)}
                tipExtra={(c) => {
                  if (effMode !== 'rel') return null
                  const v = getValue(ds, c, indicator.id, year)
                  return v == null ? null : { label: 'waarde', value: fmtValue(v, indicator.unit) }
                }}
                hovered={hoverCode}
                onHover={setHoverCode}
                ariaLabel={`Kaart: ${indicator.label}, ${year}`}
                noDataReason={(c) => noDataReason(ds, c, indicator, year)}
              />
            ) : (
              <p className="view-sub">
                Geen kaart beschikbaar voor dit niveau
                {state.level === 'stadsdeel' ? ' (kies gebieden, wijken of buurten)' : ''}.
              </p>
            )}
          </div>
          <div className="card">
            <h3 className="card-title">
              Top {topRows.length} {levelNaam}
            </h3>
            <p className="card-sub">
              {indicator.direction === 'laag'
                ? `sterkste signaal eerst (laagste waarde${effMode === 'rel' ? ` t.o.v. ${refName}` : ''})`
                : `sterkste signaal eerst (hoogste waarde${effMode === 'rel' ? ` t.o.v. ${refName}` : ''})`}
            </p>
            <BarChart
              rows={topRows}
              unit={effMode === 'rel' ? 'pct' : indicator.unit}
              onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
              onHover={setHoverCode}
              hovered={hoverCode}
            />
          </div>
        </div>
      )}

      <TabFootnote viewId="kaart" ds={ds} state={state} />
    </>
  )
}
