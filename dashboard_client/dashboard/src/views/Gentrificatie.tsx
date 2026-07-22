import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState, GeoSet } from '../App'
import { Choropleth } from '../components/Choropleth'
import { ScatterPlot, type ScatterPoint } from '../components/ScatterPlot'
import { BarChart, type BarRow } from '../components/BarChart'
import { areas, regionName } from '../lib/data'
import { computeGentrification, gentYears, type GentResult } from '../lib/gentrification'

const DIV = [
  'var(--div-neg-3)', 'var(--div-neg-2)', 'var(--div-neg-1)', 'var(--div-mid)',
  'var(--div-pos-1)', 'var(--div-pos-2)', 'var(--div-pos-3)',
]

function divColor(v: number | null | undefined, cap: number): string {
  if (v == null) return 'var(--surface-2)'
  const t = Math.max(-1, Math.min(1, v / (cap || 1)))
  const i = Math.round(t * 3) + 3
  return DIV[Math.max(0, Math.min(DIV.length - 1, i))]
}

/** Robuust symmetrisch plafond: 85e percentiel (lineair geïnterpoleerd) van
 *  |waarde|, zodat uitschieters (nieuwbouwgebieden) het middengebied niet
 *  platdrukken. Bij < 5 waarden valt het terug op de max (te weinig voor een
 *  betrouwbaar percentiel). STAT-6. */
function robustCap(values: number[]): number {
  const abs = values.map((v) => Math.abs(v)).sort((a, b) => a - b)
  if (!abs.length) return 1
  if (abs.length < 5) return Math.max(abs[abs.length - 1], 0.0001)
  const pos = (abs.length - 1) * 0.85
  const lo = Math.floor(pos)
  const frac = pos - lo
  const val = abs[lo] + frac * ((abs[lo + 1] ?? abs[lo]) - abs[lo])
  return Math.max(val, 0.0001)
}

const fmt1 = (v: number) => (v > 0 ? '+' : '') + v.toFixed(1)

export function Gentrificatie({ ds, geo, state }: { ds: Dataset; geo: GeoSet; state: AppState }) {
  const [hoverCode, setHoverCode] = useState<string | null>(null)
  const cfg = ds.gentrification

  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])
  const yrs = useMemo(() => (cfg ? gentYears(ds, cfg, list) : []), [ds, cfg, list])

  // standaardperiode: het jaarpaar dat de MEESTE gebieden een index geeft (niet de
  // breedste span) — anders arceert heel-Amsterdam ~38% (STAT-1). Bij gelijke
  // dekking wint de bredere span.
  const [defStart, defEnd] = useMemo(() => {
    if (!cfg || yrs.length < 2) return [yrs[0], yrs[yrs.length - 1]] as const
    let best: readonly [number, number] = [yrs[0], yrs[yrs.length - 1]]
    let bestScore = -1
    for (let i = 0; i < yrs.length; i++)
      for (let j = i + 1; j < yrs.length; j++) {
        const res = computeGentrification(ds, cfg, list, yrs[i], yrs[j])
        const cov = res.filter((r) => r.index != null).length
        const span = yrs[j] - yrs[i]
        const score = cov * 1000 + span // dekking eerst, dan span als tiebreak
        if (score > bestScore) { bestScore = score; best = [yrs[i], yrs[j]] }
      }
    return best
  }, [ds, cfg, list, yrs])

  const [y0, setY0] = useState<number | null>(null)
  const [y1, setY1] = useState<number | null>(null)
  // startYear mag nooit het laatste jaar zijn (anders bestaat er geen eindjaar > start
  // en ontstaat een lege begin==eindjaar-analyse na een niveau-/scope-wissel met een
  // stale y0 die het maximum van de gereduceerde jarenset werd) (L4)
  const startYear = y0 != null && yrs.includes(y0) && y0 < yrs[yrs.length - 1] ? y0 : defStart
  const endYearRaw = y1 != null && yrs.includes(y1) ? y1 : defEnd
  // val niet terug op defEnd als die zelf <= startYear is (bijv. startYear ==
  // defEnd gekozen): dat gaf een lege begin==eindjaar-analyse (L4)
  const endYear =
    endYearRaw > startYear
      ? endYearRaw
      : defEnd > startYear
        ? defEnd
        : (yrs.find((y) => y > startYear) ?? yrs[yrs.length - 1])

  const results = useMemo(() => {
    if (!cfg || yrs.length < 2) return []
    return computeGentrification(ds, cfg, list, startYear, endYear)
  }, [ds, cfg, list, yrs, startYear, endYear])

  const withIndex = results.filter((r) => r.index != null)
  const cap = robustCap(withIndex.map((r) => r.index!))

  const mapValues = useMemo(() => {
    const o: Record<string, number | null> = {}
    for (const r of results) o[r.code] = r.index
    return o
  }, [results])

  const mapGeo = useMemo(() => {
    const g = state.level === 'buurt' ? geo.buurt : state.level === 'gebied' ? geo.gebied : geo.wijk
    if (!g || state.level === 'stadsdeel') return null
    const codes = new Set(list.map((a) => a.code))
    return { ...g, features: g.features.filter((f) => codes.has(f.properties.code)) }
  }, [geo, state.level, list])

  const byCode = useMemo(() => Object.fromEntries(results.map((r) => [r.code, r])), [results])

  const barRows: BarRow[] = useMemo(() => {
    // alleen gebieden met >=2 van de 4 signalen ranken; een index uit 1 component
    // is te wankel voor een top-lijst (STAT-4)
    const r = withIndex
      .filter((x) => x.coverage >= 2)
      .map((x) => ({
        code: x.code,
        label: x.name,
        value: x.index,
        highlight: state.selectedArea === x.code,
      }))
    r.sort((a, b) => (b.value ?? 0) - (a.value ?? 0))
    return r.slice(0, 14)
  }, [withIndex, state.selectedArea])

  const scatter: ScatterPoint[] = useMemo(
    () =>
      results
        .filter((r) => r.wozChange != null && r.liChange != null)
        .map((r) => ({
          code: r.code,
          label: r.name,
          x: r.wozChange!,
          y: r.liChange!,
          value: r.index,
          highlight: state.selectedArea === r.code,
        })),
    [results, state.selectedArea],
  )

  const levelNaam = state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : 'wijken'
  const sel: GentResult | undefined = state.selectedArea ? byCode[state.selectedArea] : undefined

  if (!cfg) return <p className="view-sub">Geen gentrificatieconfiguratie in de dataset.</p>

  if (yrs.length < 2)
    return (
      <>
        <h1 className="view-title">Gentrificatie-analyse</h1>
        <div className="card">
          <div className="empty-state">
            <p>
              Onvoldoende woningmarkt- en inkomensdata op {levelNaam}-niveau voor deze gemeente om een
              ontwikkeling te berekenen. Deze analyse werkt het best voor Amsterdam op wijk-, gebieds-
              of stadsdeelniveau.
            </p>
          </div>
        </div>
      </>
    )

  return (
    <>
      <h1 className="view-title">Gentrificatie-analyse {startYear}–{endYear}</h1>
      <p className="view-sub">
        Een samengestelde index van vier CBS-signalen — stijgende woningwaarde, stijgend inkomen,
        krimpende sociale huur en dalend aandeel lage inkomens. Elk signaal is gestandaardiseerd
        t.o.v. de andere {levelNaam}; <strong>positief betekent: gentrificeert sneller dan gemiddeld</strong>.
        Signalerend, geen bewijs van individuele verdringing.
      </p>

      <div className="filterbar" style={{ padding: '0 0 14px', maxWidth: 'none' }}>
        <label>Periode</label>
        <select
          className="control"
          value={startYear}
          onChange={(e) => setY0(Number(e.target.value))}
          aria-label="Beginjaar"
        >
          {yrs.slice(0, -1).map((y) => (
            <option key={y} value={y}>{y}</option>
          ))}
        </select>
        <span className="view-sub" style={{ margin: 0 }}>tot</span>
        <select
          className="control"
          value={endYear}
          onChange={(e) => setY1(Number(e.target.value))}
          aria-label="Eindjaar"
        >
          {yrs.filter((y) => y > startYear).map((y) => (
            <option key={y} value={y}>{y}</option>
          ))}
        </select>
        <span className="view-sub" style={{ margin: 0 }}>
          · {withIndex.length} van {list.length} {levelNaam} met voldoende data
        </span>
      </div>

      <div className="grid-map">
        <div className="card">
          <h3 className="card-title">Gentrificatie-index per {levelNaam.slice(0, -2)}{levelNaam.endsWith('en') ? '' : ''} · {startYear}–{endYear}</h3>
          <p className="card-sub">rood = gentrificeert sneller dan gemiddeld · blauw = blijft achter of stabiliseert</p>
          {mapGeo && mapGeo.features.length > 0 ? (
            <Choropleth
              geo={mapGeo}
              values={mapValues}
              unit="index"
              mode="div"
              domain={{ min: -cap, max: cap }}
              height={430}
              selected={state.selectedArea}
              onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
              labelFor={(c) => regionName(ds, c)}
              hovered={hoverCode}
              onHover={setHoverCode}
              ariaLabel={`Gentrificatie-index ${startYear} tot ${endYear}`}
              divLabels={{ low: 'blijft achter', high: 'gentrificeert sneller' }}
              tipExtra={(c) => {
                const r = byCode[c]
                return r?.index != null ? { label: 'index', value: fmt1(r.index) } : null
              }}
              noDataReason={(c) => {
                const r = byCode[c]
                const missing = cfg.components
                  .filter((comp) => r?.components[comp.id]?.z == null)
                  .map((comp) => comp.label)
                if (missing.length === cfg.components.length || !r)
                  return `Geen van de vier signalen (WOZ, inkomen, sociale huur, lage inkomens) ` +
                    `is voor beide jaren (${startYear}, ${endYear}) beschikbaar in dit gebied`
                return `Onvoldoende signalen voor een index: ontbrekend voor ${startYear}–${endYear} — ` +
                  missing.join(', ').toLowerCase()
              }}
            />
          ) : (
            <p className="view-sub">Geen kaart op dit niveau — kies gebieden, wijken of buurten.</p>
          )}
        </div>

        <div className="card">
          <h3 className="card-title">Verdringingspatroon</h3>
          <p className="card-sub">
            woningwaarde-stijging (horizontaal) × verandering aandeel lage inkomens (verticaal)
          </p>
          {scatter.length > 0 ? (
            <ScatterPlot
              points={scatter}
              xLabel="WOZ-stijging"
              yLabel="Δ lage inkomens"
              xRef={0}
              yRef={0}
              quadrants={{
                tr: 'prijzen ↑, doelgroep blijft',
                br: 'verdringing: prijzen ↑, lage ink. ↓',
                bl: 'prijzen ↓, lage ink. ↓',
                tl: 'verarming: prijzen ↓, lage ink. ↑',
              }}
              fmtX={(v) => `${fmt1(v)}%`}
              fmtY={(v) => `${fmt1(v)} pp`}
              colorFor={(v) => divColor(v, cap)}
              height={430}
              onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
              onHover={setHoverCode}
              hovered={hoverCode}
            />
          ) : (
            <p className="view-sub">Geen WOZ/inkomensdata voor beide jaren op dit niveau.</p>
          )}
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <div>
            <h3 className="card-title">Sterkste gentrificatie (top {barRows.length})</h3>
            <p className="card-sub">samengestelde index; klik voor de opbouw uit de vier signalen</p>
          </div>
        </div>
        <BarChart
          rows={barRows}
          unit="index"
          color="var(--div-pos-2)"
          onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
          onHover={setHoverCode}
          hovered={hoverCode}
        />
      </div>

      {sel && sel.index != null && (
        <div className="card">
          <h3 className="card-title">Opbouw index — {sel.name}</h3>
          <p className="card-sub">
            index {fmt1(sel.index)} · {startYear}–{endYear} · bijdrage per signaal (z-score × richting)
          </p>
          <div className="gent-components">
            {cfg.components.map((c) => {
              const comp = sel.components[c.id]
              const z = comp?.z ?? null
              const w = z == null ? 0 : Math.min(100, (Math.abs(z) / (cap * 1.5 || 1)) * 100)
              return (
                <div key={c.id} className="gent-comp-row">
                  <span className="gent-comp-label" title={c.why}>{c.label}</span>
                  <span className="gent-comp-change">
                    {comp?.change == null ? '–' : `${fmt1(comp.change)}${c.mode === 'pct' ? '%' : ' pp'}`}
                  </span>
                  <span className="gent-comp-bar">
                    <span
                      className="gent-comp-fill"
                      style={{
                        width: `${w}%`,
                        // negatief: balk loopt zuiver naar links vanaf het midden (symmetrisch
                        // met positief, dat vanaf het midden naar rechts loopt) — voorheen
                        // stond de balk gecentreerd op het midden, waardoor hij half zo lang
                        // leek en deels aan de positieve kant uitstak (M10)
                        marginLeft: z != null && z < 0 ? `${50 - w}%` : '50%',
                        background: z == null ? 'var(--surface-2)' : z >= 0 ? 'var(--div-pos-2)' : 'var(--div-neg-2)',
                      }}
                    />
                  </span>
                  <span className="gent-comp-z">{z == null ? '–' : fmt1(z)}</span>
                </div>
              )
            })}
          </div>
          <p className="view-sub" style={{ marginTop: 10 }}>
            {cfg.components.map((c) => c.label).join(', ')} — {cfg.note}
          </p>
        </div>
      )}
    </>
  )
}
