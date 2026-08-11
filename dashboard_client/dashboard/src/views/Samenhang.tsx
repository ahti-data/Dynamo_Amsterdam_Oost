import { useEffect, useMemo, useState } from 'react'
import type { Dataset, Indicator } from '../types'
import type { AppState, GeoSet } from '../App'
import { Heatmap, type HeatCell, type HeatAxis } from '../components/Heatmap'
import { ScatterPlot, type ScatterPoint } from '../components/ScatterPlot'
import { Choropleth } from '../components/Choropleth'
import { areas, availableYears, indicatorById, regionName, nearestYear, getValue, toCsv, downloadCsv, noDataReason } from '../lib/data'
import { correlate, fisherCI, approxP, strength, type Method } from '../lib/correlation'
import { fmtValue } from '../lib/format'
import { BronLink } from '../components/BronLink'
import { TabFootnote } from '../components/TabFootnote'

// curated socio-demografische X-set (relatief; geen absolute aantallen)
const X_DEFAULT = [
  'p_hh_li', 'p_ink_ar', 'g_ink_pi', 'm_hh_ver', 'p_arb_pp',
  'p_neu_al', 'p_65_oo', 'p_00_14', 'p_15_24', 'p_1p_hh', 'p_hh_m_k',
  'p_wcorpw', 'g_wozbag', 'g_afs_hp',
]
const fmtR = (r: number | null) => (r == null ? '–' : (r > 0 ? '+' : '') + r.toFixed(2))

export function Samenhang({ ds, geo, state }: { ds: Dataset; geo: GeoSet; state: AppState }) {
  const [method, setMethod] = useState<Method>('spearman')
  // standaard aan: het ontwerpdoc schrijft voor dat onzekere cellen (n=8-11)
  // altijd gedempt worden getoond, niet als opt-in (M8)
  const [damp, setDamp] = useState(true)
  const [sel, setSel] = useState<{ x: string; y: string } | null>(null)
  const [changeMode, setChangeMode] = useState(false)
  const [hoverCode, setHoverCode] = useState<string | null>(null)

  // deep-link vanuit Inzichten: neem het voorgeselecteerde X-Y-paar over
  useEffect(() => {
    if (state.pendingPair) {
      setSel(state.pendingPair)
      state.clearPendingPair()
    }
  }, [state.pendingPair])

  // stabiele referentie zodat de over-tijd/Δ-memo's niet elke render herberekenen (PERF-1)
  const meetjaren = useMemo(() => ds.correlation?.rivmMeetjaren ?? [2016, 2020, 2022, 2024], [ds])
  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])
  const year = nearestYear(meetjaren.filter((y) => ds.years.includes(y)), state.year)

  // X = curated socio-demografische indicatoren met data op dit niveau/jaar
  const xInds = useMemo(
    () =>
      X_DEFAULT.map((id) => indicatorById(ds, id))
        .filter((i): i is Indicator => !!i && availableYears(ds, list, i.id).includes(year)),
    [ds, list, year],
  )
  // Y = uitkomstindicatoren met data op dit niveau/jaar
  const yInds = useMemo(
    () =>
      ds.indicators
        .filter((i) => i.isOutcome && availableYears(ds, list, i.id).includes(year)),
    [ds, list, year],
  )

  // correlatiematrix (memo): cache per (x,y)
  const cells = useMemo(() => {
    const m = new Map<string, HeatCell>()
    for (const x of xInds)
      for (const y of yInds) {
        const c = correlate(ds, list, x.id, y.id, year, method)
        m.set(`${x.id}|${y.id}`, {
          r: c.r, n: c.n, ci: fisherCI(c.r, c.n, method), p: approxP(c.r, c.n),
          weak: c.n < 8,
        })
      }
    return m
  }, [ds, list, xInds, yInds, year, method])

  const rows: HeatAxis[] = xInds.map((i) => ({ id: i.id, label: i.shortLabel }))
  const cols: HeatAxis[] = yInds.map((i) => ({ id: i.id, label: i.shortLabel }))
  const cellFor = (x: string, y: string): HeatCell =>
    cells.get(`${x}|${y}`) ?? { r: null, n: 0, ci: null, p: null, weak: true }

  const enoughAreas = list.length >= 8
  const hasMatrix = enoughAreas && rows.length > 0 && cols.length > 0

  // sterkste verbanden: minstens 12 gebieden (kleine-N-toevalspieken weren, STAT-3)
  // en sorteren op de ondergrens van het 95%-interval i.p.v. op ruwe |r|
  const STRONG_MIN_N = 12
  const strongest = useMemo(() => {
    const arr: { x: string; y: string; r: number; n: number; lo: number }[] = []
    for (const [k, c] of cells)
      if (c.r != null && c.n >= STRONG_MIN_N) {
        const [x, y] = k.split('|')
        // BI dat nul omvat betekent dat de ondergrens van |r| feitelijk 0 is (K1)
        const lo = c.ci ? (c.ci.lo <= 0 && c.ci.hi >= 0 ? 0 : Math.min(Math.abs(c.ci.lo), Math.abs(c.ci.hi))) : 0
        arr.push({ x, y, r: c.r, n: c.n, lo })
      }
    arr.sort((a, b) => b.lo - a.lo)
    return arr.slice(0, 10)
  }, [cells])

  // toon de puntenwolk standaard met het sterkste verband i.p.v. pas na een
  // klik op de matrix — anders was niet duidelijk dat de puntenwolk bestond
  useEffect(() => {
    if (sel || state.pendingPair || !hasMatrix) return
    if (strongest.length > 0) {
      setSel({ x: strongest[0].x, y: strongest[0].y })
      return
    }
    const anyPair = [...cells.entries()].find(([, c]) => c.r != null)
    if (anyPair) {
      const [x, y] = anyPair[0].split('|')
      setSel({ x, y })
    } else if (xInds[0] && yInds[0]) {
      setSel({ x: xInds[0].id, y: yInds[0].id })
    }
  }, [sel, state.pendingPair, hasMatrix, strongest, cells, xInds, yInds])

  // drilldown-selectie
  const xInd = sel ? indicatorById(ds, sel.x) : undefined
  const yInd = sel ? indicatorById(ds, sel.y) : undefined
  const drill = useMemo(
    () => (sel ? correlate(ds, list, sel.x, sel.y, year, method) : null),
    [ds, list, sel, year, method],
  )

  const scatterPoints: ScatterPoint[] = useMemo(() => {
    if (!drill || changeMode) return []
    return drill.pairs.map((p) => ({
      code: p.code, label: p.name, x: p.x, y: p.y, highlight: hoverCode === p.code,
    }))
  }, [drill, changeMode, hoverCode])

  // verandering-vs-verandering (ΔX vs ΔY over de meetjaren-periode)
  const changePoints: ScatterPoint[] = useMemo(() => {
    if (!sel || !changeMode) return []
    const y0 = meetjaren[0], y1 = meetjaren[meetjaren.length - 1]
    const pts: ScatterPoint[] = []
    for (const a of list) {
      const x0 = getValue(ds, a.code, sel.x, y0), x1 = getValue(ds, a.code, sel.x, y1)
      const yy0 = getValue(ds, a.code, sel.y, y0), yy1 = getValue(ds, a.code, sel.y, y1)
      if (x0 == null || x1 == null || yy0 == null || yy1 == null) continue
      pts.push({ code: a.code, label: a.name, x: x1 - x0, y: yy1 - yy0, highlight: hoverCode === a.code })
    }
    return pts
  }, [ds, list, sel, changeMode, meetjaren, hoverCode])

  // mini-kaart van de gekozen X over de gebieden
  const mapGeo = useMemo(() => {
    const g = state.level === 'buurt' ? geo.buurt : state.level === 'gebied' ? geo.gebied : geo.wijk
    if (!g || state.level === 'stadsdeel') return null
    const codes = new Set(list.map((a) => a.code))
    return { ...g, features: g.features.filter((f) => codes.has(f.properties.code)) }
  }, [geo, state.level, list])
  const mapValues = useMemo(() => {
    const o: Record<string, number | null> = {}
    if (sel) for (const a of list) o[a.code] = getValue(ds, a.code, sel.x, year)
    return o
  }, [ds, list, sel, year])

  const exportCsv = () => {
    const header = ['Gebiedskenmerk (X)', 'Uitkomst (Y)', method === 'spearman' ? 'Spearman rho' : 'Pearson r', 'n', '95%-BI onder', '95%-BI boven', 'sterkte']
    const body: (string | number)[][] = []
    for (const x of xInds) for (const y of yInds) {
      const c = cellFor(x.id, y.id)
      body.push([x.label, y.label, c.r == null ? '' : String(c.r).replace('.', ','), c.n,
        c.ci ? String(c.ci.lo).replace('.', ',') : '', c.ci ? String(c.ci.hi).replace('.', ',') : '',
        strength(c.r)])
    }
    downloadCsv(`samenhang-${ds.meta.gemeente}-${state.scope || 'gemeente'}-${state.level}-${year}.csv`, toCsv(header, body))
  }

  // ruwe onderliggende waarden (geen afgeleide coëfficiënten): per gebied alle
  // X- en Y-indicatoren in het analysejaar, de data waarop de matrix hierboven is gebaseerd
  const exportRawData = () => {
    const header = ['Gebied', ...xInds.map((x) => x.label), ...yInds.map((y) => y.label)]
    const body: (string | number)[][] = list.map((a) => [
      a.name,
      ...xInds.map((x) => {
        const v = getValue(ds, a.code, x.id, year)
        return v == null ? '' : String(v).replace('.', ',')
      }),
      ...yInds.map((y) => {
        const v = getValue(ds, a.code, y.id, year)
        return v == null ? '' : String(v).replace('.', ',')
      }),
    ])
    downloadCsv(
      `samenhang-data-${ds.meta.gemeente}-${state.scope || 'gemeente'}-${state.level}-${year}.csv`,
      toCsv(header, body),
    )
  }

  const levelNaam = state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : state.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'

  return (
    <>
      <h1 className="view-title">Samenhang — gebiedskenmerken × uitkomsten</h1>
      <p className="view-sub view-sub-wide">
        Correlatie tussen socio-demografische kenmerken (X) en zorg-/welzijns-/gezondheidsuitkomsten
        (Y), berekend <strong>over de {levelNaam}</strong> binnen de gekozen focus. RIVM-meetjaar{' '}
        <strong>{year}</strong>
        {year !== state.year ? ` (dichtst bij gekozen peiljaar ${state.year})` : ''}.
      </p>
      <div className="notice" role="note">
        ⚠ Dit is een <strong>ecologisch, verkennend</strong> verband tussen gebiedsgemiddelden — geen
        individueel of causaal bewijs. Uitkomsten zijn gemodelleerde{' '}
        <BronLink state={state} id="rivm-gezondheid">RIVM-schattingen</BronLink>. Meerdere
        sterke verbanden met inkomen/opleiding/armoede meten deels dezelfde onderliggende factor.
      </div>

      <div className="filterbar" style={{ padding: '0 0 12px', maxWidth: 'none' }}>
        <label>Methode</label>
        <div className="seg" role="group" aria-label="Methode">
          <button className={method === 'spearman' ? 'active' : ''} onClick={() => setMethod('spearman')}>
            Spearman ρ
          </button>
          <button className={method === 'pearson' ? 'active' : ''} onClick={() => setMethod('pearson')}>
            Pearson r
          </button>
        </div>
        <label style={{ marginLeft: 8 }}>
          <input type="checkbox" checked={damp} onChange={(e) => setDamp(e.target.checked)} /> onzekere
          cellen dempen
        </label>
        <button className="control" onClick={exportCsv} style={{ backgroundImage: 'none', marginLeft: 'auto' }}>
          ↓ Exporteer matrix (CSV)
        </button>
      </div>

      {!enoughAreas ? (
        <div className="card">
          <div className="empty-state">
            <p>
              Te weinig gebieden ({list.length}) voor een betrouwbare samenhang. Kies een ruimere
              focus of een fijner niveau (bijv. buurten).
            </p>
          </div>
        </div>
      ) : rows.length === 0 || cols.length === 0 ? (
        <div className="card">
          <div className="empty-state">
            <p>Geen X- of Y-indicatoren met data op dit niveau in {year}.</p>
          </div>
        </div>
      ) : (
        <>
          <div className="card">
            <div className="card-head">
              <div>
                <h3 className="card-title">Correlatiematrix · {year} · {list.length} {levelNaam}</h3>
                <p className="card-sub">
                  rood = positieve samenhang, blauw = negatieve · klik een cel voor het detail ·
                  celtekst = coëfficiënt
                </p>
              </div>
            </div>
            <Heatmap
              rows={rows}
              cols={cols}
              cell={cellFor}
              dampUncertain={damp}
              selected={sel}
              onSelect={(x, y) => setSel({ x, y })}
            />
          </div>

          {sel && xInd && yInd && drill && (
            <div className="card">
              <div className="card-head">
                <div>
                  <h3 className="card-title">
                    {xInd.shortLabel} ↔ {yInd.shortLabel}
                  </h3>
                  <p className="card-sub">
                    {method === 'spearman' ? 'Spearman ρ' : 'Pearson r'} = <strong>{fmtR(drill.r)}</strong>{' '}
                    ({strength(drill.r)}) · n = {drill.n}
                    {(() => {
                      const ci = fisherCI(drill.r, drill.n, method)
                      return ci ? ` · 95%-BI ${fmtR(ci.lo)}…${fmtR(ci.hi)}` : ''
                    })()}
                    {' '}· Y = gemodelleerde schatting
                  </p>
                </div>
                <div className="seg" role="group" aria-label="Weergave">
                  <button className={!changeMode ? 'active' : ''} onClick={() => setChangeMode(false)}>
                    Per jaar
                  </button>
                  <button className={changeMode ? 'active' : ''} onClick={() => setChangeMode(true)}>
                    Δ {meetjaren[0]}→{meetjaren[meetjaren.length - 1]}
                  </button>
                </div>
              </div>
              <div className="grid-map">
                <ScatterPlot
                  points={changeMode ? changePoints : scatterPoints}
                  xLabel={changeMode ? `Δ ${xInd.shortLabel}` : xInd.shortLabel}
                  yLabel={changeMode ? `Δ ${yInd.shortLabel}` : yInd.shortLabel}
                  xRef={changeMode ? 0 : undefined}
                  yRef={changeMode ? 0 : undefined}
                  fmtX={(v) => (changeMode ? (v > 0 ? '+' : '') : '') + fmtValue(v, xInd.unit)}
                  fmtY={(v) => (changeMode ? (v > 0 ? '+' : '') : '') + fmtValue(v, yInd.unit)}
                  colorFor={() => 'var(--series-1)'}
                  trendLine={!changeMode ? (drill.slope != null && drill.intercept != null ? { slope: drill.slope, intercept: drill.intercept } : null) : null}
                  height={360}
                  onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
                  onHover={setHoverCode}
                  hovered={hoverCode}
                />
                <div>
                  <p className="card-sub">
                    {changeMode
                      ? 'Robuustheidscheck: veranderde X samen met veranderde Y? Dubbel verschil, veel ruis, kleine N.'
                      : `Kaart van ${xInd.shortLabel} over de ${levelNaam}; hover synchroniseert met de puntenwolk. ` +
                        'Let op: hier betekent kleur de hóógte van de waarde (donker = hoog), niet de samenhang uit de matrix.'}
                  </p>
                  {!changeMode && mapGeo && mapGeo.features.length > 0 && (
                    <Choropleth
                      geo={mapGeo}
                      values={mapValues}
                      unit={xInd.unit}
                      mode="seq"
                      invert={xInd.direction === 'laag'}
                      height={300}
                      selected={state.selectedArea}
                      onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
                      labelFor={(c) => regionName(ds, c)}
                      hovered={hoverCode}
                      onHover={setHoverCode}
                      ariaLabel={`Kaart ${xInd.label}`}
                      noDataReason={(c) => noDataReason(ds, c, xInd, year)}
                    />
                  )}
                </div>
              </div>
            </div>
          )}

          <div className="filterbar" style={{ padding: '4px 0 0', maxWidth: 'none' }}>
            <button className="control" onClick={exportRawData} style={{ backgroundImage: 'none' }}>
              ↓ Download alle onderliggende data (CSV)
            </button>
          </div>
        </>
      )}

      <TabFootnote viewId="samenhang" ds={ds} state={state} />
    </>
  )
}
