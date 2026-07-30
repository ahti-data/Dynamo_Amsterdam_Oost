import { useEffect, useMemo, useState } from 'react'
import type { Dataset, Indicator } from '../types'
import type { AppState, GeoSet } from '../App'
import { Heatmap, type HeatCell, type HeatAxis } from '../components/Heatmap'
import { ScatterPlot, type ScatterPoint } from '../components/ScatterPlot'
import { LineChart, type LineSeries } from '../components/LineChart'
import { DataTable, type TableColumn, type TableRowData } from '../components/DataTable'
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

  // correlatie over tijd: r per meetjaar voor het gekozen paar
  const overTime: LineSeries[] = useMemo(() => {
    if (!sel) return []
    const vals = ds.years.map((yr) =>
      meetjaren.includes(yr) ? correlate(ds, list, sel.x, sel.y, yr, method).r : null,
    )
    return [{ id: 'r', label: `${method === 'spearman' ? 'Spearman ρ' : 'Pearson r'}`, color: 'var(--series-1)', values: vals }]
  }, [ds, list, sel, method, meetjaren])

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

  const levelNaam = state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : state.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'

  return (
    <>
      <h1 className="view-title">Samenhang — gebiedskenmerken × uitkomsten</h1>
      <p className="view-sub">
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
              <div style={{ marginTop: 12 }}>
                <h3 className="card-title">Samenhang over tijd</h3>
                <p className="card-sub">
                  {method === 'spearman' ? 'Spearman ρ' : 'Pearson r'} per RIVM-meetjaar — stabiel,
                  sterker wordend of verdwijnend verband?
                </p>
                <LineChart
                  years={ds.years}
                  series={overTime}
                  unit="index"
                  height={220}
                  yDomain={[-1, 1]}
                  zeroLine
                />
              </div>
            </div>
          )}

          <div className="card">
            <h3 className="card-title">Sterkste verbanden · {year}</h3>
            <p className="card-sub">
              gesorteerd op de ondergrens van het 95%-interval (n ≥ {STRONG_MIN_N}); let op
              dubbeltelling van SES-achtige kenmerken (inkomen/opleiding/armoede meten deels hetzelfde)
            </p>
            <div className="strong-list">
              {strongest.map((s) => {
                const xi = indicatorById(ds, s.x), yi = indicatorById(ds, s.y)
                return (
                  <button
                    key={`${s.x}|${s.y}`}
                    className={`strong-row${sel?.x === s.x && sel?.y === s.y ? ' active' : ''}`}
                    onClick={() => setSel({ x: s.x, y: s.y })}
                  >
                    <span className="strong-pair">{xi?.shortLabel} ↔ {yi?.shortLabel}</span>
                    <span className="strong-bar">
                      <span
                        className="strong-fill"
                        style={{
                          width: `${Math.abs(s.r) * 100}%`,
                          marginLeft: s.r < 0 ? `${(1 - Math.abs(s.r)) * 100}%` : '0',
                          background: s.r >= 0 ? 'var(--div-pos-2)' : 'var(--div-neg-2)',
                        }}
                      />
                    </span>
                    <span className="strong-r">{fmtR(s.r)}</span>
                  </button>
                )
              })}
              {strongest.length === 0 && <p className="view-sub">Geen verbanden met voldoende gebieden.</p>}
            </div>
          </div>

          <div className="card">
            <h3 className="card-title">Alle coëfficiënten</h3>
            <p className="card-sub">sorteerbaar; leeg = te weinig gebieden of geen data</p>
            <CorrTable xInds={xInds} yInds={yInds} cellFor={cellFor} onSelect={(x, y) => setSel({ x, y })} />
          </div>
        </>
      )}

      <TabFootnote viewId="samenhang" ds={ds} state={state} />
    </>
  )
}

/** Platte tabel van alle X-Y-coëfficiënten (hergebruikt DataTable-styling niet 1:1;
 *  eigen compacte tabel omdat de cellen kruisverbanden zijn). */
function CorrTable({
  xInds, yInds, cellFor, onSelect,
}: {
  xInds: Indicator[]
  yInds: Indicator[]
  cellFor: (x: string, y: string) => HeatCell
  onSelect: (x: string, y: string) => void
}) {
  const columns: TableColumn[] = [
    { id: 'r', label: 'coëff.', unit: 'index' },
    { id: 'n', label: 'n', unit: 'aantal' },
  ]
  const rows: TableRowData[] = []
  for (const x of xInds)
    for (const y of yInds) {
      const c = cellFor(x.id, y.id)
      if (c.r == null) continue
      rows.push({
        code: `${x.id}|${y.id}`,
        name: `${x.shortLabel} ↔ ${y.shortLabel}`,
        values: { r: c.r, n: c.n },
      })
    }
  return (
    <DataTable
      columns={columns}
      rows={rows}
      onSelect={(code) => {
        const [x, y] = code.split('|')
        onSelect(x, y)
      }}
    />
  )
}
