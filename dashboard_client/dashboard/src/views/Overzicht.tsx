import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, GeoSet } from '../App'
import { StatTile } from '../components/StatTile'
import { BarChart, type BarRow } from '../components/BarChart'
import { Choropleth } from '../components/Choropleth'
import { SegmentedPicker } from '../components/SegmentedPicker'
import { TabFootnote } from '../components/TabFootnote'
import {
  areas, availableYears, getSeries, getValue, deltaOverPeriod,
  indicatorById, regionName, nearestYear, signalSort, noDataReason, coverageFrac,
} from '../lib/data'
import { fmtValue } from '../lib/format'

export function Overzicht({ ds, geo, state }: { ds: Dataset; geo: GeoSet; state: AppState }) {
  // hover-koppeling tussen staafgrafiek en kaart
  const [hoverCode, setHoverCode] = useState<string | null>(null)
  // alleen thema's met indicatoren (leeg thema zou crashen — CRASH-1)
  const themes = ds.themes.filter((t) => t.indicatorIds.length > 0)
  const theme = themes.find((t) => t.id === state.themeId) ?? themes[0]
  // lidmaatschap via de themalijst — indicatoren kunnen in meerdere thema's zitten
  const indicator =
    (theme.indicatorIds.includes(state.indicatorId) ? indicatorById(ds, state.indicatorId) : undefined) ??
    indicatorById(ds, theme.headline[0] ?? theme.indicatorIds[0]) ??
    ds.indicators[0]

  const focusCode = state.scope || ds.meta.gemeente
  const focusRegion = ds.regions.find((r) => r.code === focusCode)
  const focusName = focusRegion?.name ?? focusCode

  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])

  // beschikbaarheid per scope × niveau, niet gemeentebreed (review #2)
  const availYears = useMemo(
    () => availableYears(ds, list, indicator.id),
    [ds, list, indicator.id],
  )
  const dataYear = nearestYear(availYears, state.year)
  const hasLevelData = availYears.length > 0

  const rows: BarRow[] = useMemo(() => {
    const cmp = signalSort(indicator.direction)
    const r = list.map((a) => ({
      code: a.code,
      label: a.name,
      value: getValue(ds, a.code, indicator.id, dataYear),
      highlight: state.selectedArea === a.code,
    }))
    r.sort((x, y) => cmp(x.value, y.value))
    return r.slice(0, 18)
  }, [ds, list, indicator, dataYear, state.selectedArea])

  const gmValue = getValue(ds, ds.meta.gemeente, indicator.id, dataYear)
  const mapValues = useMemo(() => {
    const o: Record<string, number | null> = {}
    for (const a of list) o[a.code] = getValue(ds, a.code, indicator.id, dataYear)
    return o
  }, [ds, list, indicator.id, dataYear])

  const mapGeo = useMemo(() => {
    const g = state.level === 'buurt' ? geo.buurt : state.level === 'gebied' ? geo.gebied : geo.wijk
    if (!g || state.level === 'stadsdeel') return null
    const codes = new Set(list.map((a) => a.code))
    return { ...g, features: g.features.filter((f) => codes.has(f.properties.code)) }
  }, [geo, state.level, list])

  // gebieden/stadsdelen met onvolledige wijkdekking in dit jaar: hun absolute
  // totalen zijn onderschat en niet vergelijkbaar met volgedekte jaren (H1)
  const underCovered = useMemo(
    () =>
      list
        .map((a) => ({ name: a.name, frac: coverageFrac(ds, a.code, dataYear) }))
        .filter((x) => x.frac != null && x.frac < 0.999),
    [ds, list, dataYear],
  )

  const levelNaam =
    state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : state.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'
  const richtingTekst =
    indicator.direction === 'laag'
      ? 'gesorteerd op sterkste ondersteuningssignaal (laagste waarde eerst)'
      : indicator.direction === 'hoog'
        ? 'gesorteerd op sterkste ondersteuningssignaal (hoogste waarde eerst)'
        : 'gesorteerd op hoogste waarde (neutrale indicator)'

  return (
    <>
      <h1 className="view-title">
        Overzicht {focusName} — {dataYear}
      </h1>
      <p className="view-sub">
        Kies een thema (gekoppeld aan een vorm van Dynamo-dienstverlening) en zie in één oogopslag de
        doelgroepomvang, de ontwikkeling tot het gekozen peiljaar en de spreiding over de {levelNaam}.
        {focusRegion?.members === 1 ? ' Let op: dit focusgebied bestaat uit één wijk (dekking 1/1).' : ''}
      </p>

      {dataYear !== state.year && hasLevelData && (
        <p className="notice" role="status">
          ⚠ Voor {state.year} is er geen {indicator.shortLabel.toLowerCase()}-data op dit niveau —
          weergegeven wordt <strong>{dataYear}</strong> (dichtstbijzijnde beschikbare jaargang:{' '}
          {availYears.join(', ')}).
        </p>
      )}

      {underCovered.length > 0 && (
        <p className="notice" role="status">
          ⚠ In <strong>{dataYear}</strong> is de wijkdekking van{' '}
          {underCovered.map((x) => x.name).join(', ')} onvolledig (na de Amsterdamse
          herindeling koppelen enkele wijken vóór 2023 niet). De absolute totalen van
          {underCovered.length === 1 ? ' dit gebied' : ' deze gebieden'} zijn daardoor een
          onderschatting en niet vergelijkbaar met volledig gedekte jaren.
        </p>
      )}

      <SegmentedPicker
        ariaLabel="Thema's"
        asTabs
        value={theme.id}
        options={themes.map((t) => ({ id: t.id, label: t.title }))}
        onChange={(id) => {
          state.setThemeId(id)
          const first = ds.themes.find((x) => x.id === id)!
          // behoud de indicator als die ook in het nieuwe thema zit
          if (!first.indicatorIds.includes(state.indicatorId))
            state.setIndicatorId(first.headline[0] ?? first.indicatorIds[0])
        }}
      />

      <p className="view-sub" style={{ marginTop: -8 }}>
        <strong>{theme.title}</strong> · sluit aan op: {theme.dynamoService.toLowerCase()}
      </p>

      <div className="tile-row">
        {theme.headline.map((iid) => {
          const ind = indicatorById(ds, iid)
          if (!ind) return null
          // trenddelta eindigt in het gekozen peiljaar (review #15)
          const { delta, fromYear, toYear } = deltaOverPeriod(ds, focusCode, iid, state.year)
          const focusSeries = getSeries(ds, focusCode, iid)
          const yList = ds.years.filter((_, yi) => focusSeries[yi] != null)
          const y = nearestYear(yList, state.year)
          return (
            <StatTile
              key={iid}
              label={`${ind.shortLabel}${ind.isOutcome ? ' *' : ''} · ${focusName}${y !== state.year ? ` (${y})` : ''}`}
              value={getValue(ds, focusCode, iid, y)}
              unit={ind.unit}
              delta={delta}
              deltaLabel={fromYear != null ? `${fromYear}–${toYear}` : undefined}
              trend={focusSeries}
            />
          )
        })}
      </div>

      <div className="card">
        <div className="card-head">
          <div>
            <h3 className="card-title">
              Spreiding over de {levelNaam}
              {rows.length < list.length ? ` (top ${rows.length})` : ''}
            </h3>
            <p className="card-sub">
              {indicator.label} · {dataYear} · {richtingTekst}
              {gmValue != null ? ` · ${regionName(ds, ds.meta.gemeente)}: ${fmtValue(gmValue, indicator.unit)}` : ''}
              {indicator.isOutcome ? ' · gemodelleerde RIVM-schatting, geen directe telling' : ''}
            </p>
          </div>
          <select
            className="control"
            value={indicator.id}
            onChange={(e) => state.setIndicatorId(e.target.value)}
            aria-label="Indicator"
          >
            {theme.indicatorIds.map((iid) => {
              const ind = indicatorById(ds, iid)
              if (!ind) return null
              const ok = availableYears(ds, list, iid).length > 0
              return (
                <option key={iid} value={iid} disabled={!ok}>
                  {ind.label}
                  {!ok ? ' — geen data op dit niveau' : ''}
                </option>
              )
            })}
          </select>
        </div>
        {hasLevelData ? (
          <div className="grid-map">
            <BarChart
              rows={rows}
              unit={indicator.unit}
              referenceLine={
                gmValue != null && indicator.unit !== 'aantal'
                  ? { value: gmValue, label: regionName(ds, ds.meta.gemeente) }
                  : undefined
              }
              onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
              onHover={setHoverCode}
              hovered={hoverCode}
            />
            {mapGeo && mapGeo.features.length > 0 ? (
              <Choropleth
                geo={mapGeo}
                values={mapValues}
                unit={indicator.unit}
                mode="seq"
                invert={indicator.direction === 'laag'}
                height={330}
                selected={state.selectedArea}
                onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
                labelFor={(c) => regionName(ds, c)}
                hovered={hoverCode}
                onHover={setHoverCode}
                ariaLabel={`Kaart: ${indicator.label}, ${dataYear}`}
                noDataReason={(c) => noDataReason(ds, c, indicator, dataYear)}
              />
            ) : (
              <p className="view-sub">Geen kaart beschikbaar voor dit niveau.</p>
            )}
          </div>
        ) : (
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
        )}
      </div>

      <TabFootnote viewId="overzicht" ds={ds} state={state} />
    </>
  )
}
