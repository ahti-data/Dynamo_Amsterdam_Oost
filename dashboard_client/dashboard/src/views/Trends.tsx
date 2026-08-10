import { useEffect, useMemo, useState } from 'react'
import type { Dataset, Region } from '../types'
import type { AppState } from '../App'
import { LineChart, type LineSeries } from '../components/LineChart'
import { areas, availableYears, getSeries, indicatorById, deltaOverPeriod, regionName, coverageBreakYears } from '../lib/data'
import { fmtDelta } from '../lib/format'
import { TabFootnote } from '../components/TabFootnote'

const COLORS = [
  'var(--series-1)', 'var(--series-2)', 'var(--series-3)', 'var(--series-4)',
  'var(--series-5)', 'var(--series-6)', 'var(--series-7)', 'var(--series-8)',
]
const MAX_AREAS = 6

export function Trends({ ds, state }: { ds: Dataset; state: AppState }) {
  const indicator = indicatorById(ds, state.indicatorId) ?? ds.indicators[0]
  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])
  const focusCode = state.scope || ds.meta.gemeente

  const defaultSel = useMemo(() => {
    // standaardselectie volgt de richting van de indicator (review #3):
    // bij 'laag' zijn de laagste waarden het sterkste signaal
    const missing = indicator.direction === 'laag' ? Infinity : -Infinity
    const last = (code: string) => {
      const s = getSeries(ds, code, indicator.id)
      for (let i = s.length - 1; i >= 0; i--) if (s[i] != null) return s[i]!
      return missing
    }
    const codes = list.map((a) => a.code)
    const top = [...codes]
      .sort((a, b) => (indicator.direction === 'laag' ? last(a) - last(b) : last(b) - last(a)))
      .slice(0, 4)
    if (state.selectedArea && codes.includes(state.selectedArea) && !top.includes(state.selectedArea))
      top.push(state.selectedArea)
    return top
  }, [ds, list, indicator, state.selectedArea])

  const [chosen, setChosen] = useState<string[] | null>(null)
  // indicator wisselt via de gedeelde parameterbalk boven de subtabs — reset de
  // handmatige gebiedsselectie dan naar de standaardselectie voor die indicator
  useEffect(() => setChosen(null), [state.indicatorId])
  const active = (chosen ?? defaultSel).filter((c) => list.some((a) => a.code === c))
  const shown = active.length ? active : defaultSel

  const toggle = (code: string) => {
    const cur = shown.includes(code) ? shown.filter((c) => c !== code) : [...shown, code]
    if (cur.length <= MAX_AREAS && cur.length >= 1) setChosen(cur)
  }

  // bij absolute aantallen zouden de totalen de gebiedslijnen platdrukken
  const showRefs = indicator.unit !== 'aantal'

  const series: LineSeries[] = useMemo(() => {
    const s: LineSeries[] = shown.map((code, i) => ({
      id: code,
      label: regionName(ds, code),
      color: COLORS[i % COLORS.length],
      values: getSeries(ds, code, indicator.id),
    }))
    if (showRefs) {
      if (state.scope) {
        s.push({
          id: focusCode,
          label: regionName(ds, focusCode),
          color: 'var(--text-secondary)',
          values: getSeries(ds, focusCode, indicator.id),
          reference: true,
        })
      }
      s.push({
        id: ds.meta.gemeente,
        label: regionName(ds, ds.meta.gemeente),
        color: 'var(--text-muted)',
        values: getSeries(ds, ds.meta.gemeente, indicator.id),
        reference: true,
      })
    }
    return s
  }, [ds, shown, indicator.id, showRefs, state.scope, focusCode])

  const focusDelta = deltaOverPeriod(ds, focusCode, indicator.id)
  const levelNaam = state.level === 'buurt' ? 'buurten' : state.level === 'gebied' ? 'gebieden' : state.level === 'stadsdeel' ? 'stadsdelen' : 'wijken'

  // groepeer de "gebied toevoegen"-lijst onder het niveau erboven (net als de
  // indicatorlijst per thema) — buurten onder hun wijk, wijken onder hun gebied,
  // gebieden onder hun stadsdeel; val terug op een platte lijst als een parent-code ontbreekt
  const parentField = state.level === 'buurt' ? 'wk' : state.level === 'wijk' ? 'gb' : state.level === 'gebied' ? 'sd' : null
  const addOptions = list.filter((a) => !shown.includes(a.code))
  const groupedAddOptions = useMemo(() => {
    if (!parentField) return null
    const groups = new Map<string, Region[]>()
    for (const a of addOptions) {
      const parent = a[parentField]
      if (!parent) return null
      if (!groups.has(parent)) groups.set(parent, [])
      groups.get(parent)!.push(a)
    }
    return groups
  }, [addOptions, parentField])

  // dekkingsbreuken (H1): waarschuw als een getoonde lijn een sprong in aantal
  // meetellende wijken heeft — dat geeft schijnverandering, geen echte trend
  const coverageWarnings = useMemo(() => {
    const codes = [...new Set([...shown, ...(showRefs && state.scope ? [focusCode] : []), ...(showRefs ? [ds.meta.gemeente] : [])])]
    return codes
      .map((c) => ({ code: c, years: coverageBreakYears(ds, c) }))
      .filter((w) => w.years.length > 0)
  }, [ds, shown, showRefs, state.scope, focusCode])

  return (
    <>
      <h1 className="view-title">
        Ontwikkeling over tijd {ds.years[0]}–{ds.years[ds.years.length - 1]}
      </h1>
      <p className="view-sub view-sub-wide">
        Volg per gebied hoe de doelgroep zich ontwikkelt
        {showRefs ? `, afgezet tegen ${regionName(ds, ds.meta.gemeente)} (gestippeld)` : ''}.
        {` Voeg ${levelNaam} toe via de keuzelijst (max ${MAX_AREAS}).`}
        {!showRefs
          ? ' Referentielijnen verschijnen alleen bij percentages en gemiddelden — totalen zouden de lijnen platdrukken.'
          : ''}
      </p>

      <div className="filterbar" style={{ padding: '0 0 8px', maxWidth: 'none' }}>
        <label htmlFor="trends-add-area">Gebied toevoegen</label>
        <select
          id="trends-add-area"
          className="control"
          value=""
          onChange={(e) => e.target.value && toggle(e.target.value)}
          aria-label="Gebied toevoegen"
          disabled={shown.length >= MAX_AREAS}
        >
          <option value="">
            {shown.length >= MAX_AREAS ? `max. ${MAX_AREAS} bereikt` : '+ voeg toe…'}
          </option>
          {groupedAddOptions
            ? [...groupedAddOptions.entries()].map(([parentCode, group]) => (
                <optgroup key={parentCode} label={regionName(ds, parentCode)}>
                  {group.map((a) => (
                    <option key={a.code} value={a.code}>
                      {a.name}
                    </option>
                  ))}
                </optgroup>
              ))
            : addOptions.map((a) => (
                <option key={a.code} value={a.code}>
                  {a.name}
                </option>
              ))}
        </select>

        {focusDelta.delta != null && (
          <span className="view-sub" style={{ margin: 0 }}>
            {regionName(ds, focusCode)}: {fmtDelta(focusDelta.delta, indicator.unit)} ({focusDelta.fromYear}–{focusDelta.toYear})
          </span>
        )}
      </div>

      <div className="chip-row">
        {list
          .filter((a) => shown.includes(a.code))
          .map((a) => (
            <button
              key={a.code}
              className="chip active"
              onClick={() => toggle(a.code)}
              title={`${a.name} verwijderen`}
            >
              {a.name} <span aria-hidden="true">×</span>
            </button>
          ))}
      </div>

      {coverageWarnings.length > 0 && (
        <div className="notice" role="note">
          ⚠ {coverageWarnings.map((w) => `${regionName(ds, w.code)} (${w.years.join(', ')})`).join(' · ')}:
          het aantal wijken dat in dit aggregaat meetelt, verandert rond dit jaar door een
          herindeling. De trendbreuk kan (deels) een dekkingseffect zijn, geen echte verandering.
        </div>
      )}

      <div className="card">
        <h3 className="card-title">{indicator.label}</h3>
        <p className="card-sub">
          {indicator.description}
          {(() => {
            const avail = availableYears(ds, list, indicator.id)
            return avail.length < ds.years.length ? ` · beschikbaar op dit niveau: ${avail.join(', ')}` : ''
          })()}
          {indicator.direction === 'laag' ? ' · lagere waarde = sterker ondersteuningssignaal' : ''}
          {indicator.isOutcome ? ' · gemodelleerde RIVM-schatting, geen directe telling' : ''}
        </p>
        <LineChart years={ds.years} series={series} unit={indicator.unit} height={340} />
        <div className="legend-row">
          {series.map((s) => (
            <span key={s.id} className="legend-item">
              <span
                className={`key-line${s.reference ? ' dashed' : ''}`}
                style={s.reference ? { color: s.color } : { background: s.color }}
              />
              {s.label}
            </span>
          ))}
        </div>
      </div>

      <TabFootnote viewId="trends" ds={ds} state={state} />
    </>
  )
}
