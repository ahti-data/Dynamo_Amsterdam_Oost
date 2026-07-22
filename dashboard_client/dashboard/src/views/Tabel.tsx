import { useMemo, useState } from 'react'
import type { Dataset } from '../types'
import type { AppState } from '../App'
import { DataTable, type TableColumn, type TableRowData } from '../components/DataTable'
import { NL, areas, getValue, indicatorById, regionName, toCsv, downloadCsv } from '../lib/data'
import { fmtValue } from '../lib/format'

export function Tabel({ ds, state }: { ds: Dataset; state: AppState }) {
  const [relative, setRelative] = useState(false)
  const [refChoice, setRefChoice] = useState<'gemeente' | 'scope'>('gemeente')
  const theme = ds.themes.find((t) => t.id === state.themeId) ?? ds.themes[0]
  const list = useMemo(() => areas(ds, state.level, state.scope), [ds, state.level, state.scope])
  const refCode = refChoice === 'scope' && state.scope ? state.scope : ds.meta.gemeente

  const columns: TableColumn[] = useMemo(
    () =>
      theme.indicatorIds
        .map((iid) => indicatorById(ds, iid))
        .filter((i): i is NonNullable<typeof i> => i != null)
        // outcome-indicatoren (o_*) zijn RIVM-modelschattingen, geen directe telling (M7)
        .map((i) => ({ id: i.id, label: i.shortLabel + (i.isOutcome ? ' *' : ''), unit: i.unit })),
    [ds, theme],
  )
  const hasOutcomeCol = useMemo(
    () => theme.indicatorIds.some((iid) => indicatorById(ds, iid)?.isOutcome),
    [ds, theme],
  )

  const mkRow = (code: string, reference = false): TableRowData => ({
    code,
    name: regionName(ds, code),
    reference,
    values: Object.fromEntries(columns.map((c) => [c.id, getValue(ds, code, c.id, state.year)])),
  })

  const rows = useMemo(
    () => [
      ...(state.scope ? [mkRow(state.scope, true)] : []),
      ...list.map((a) => mkRow(a.code)),
    ],
    [ds, columns, state.year, list, state.scope],
  )
  const refRows = useMemo(
    () => [mkRow(ds.meta.gemeente, true), mkRow(NL, true)],
    [ds, columns, state.year],
  )
  const referenceRow = useMemo(() => mkRow(refCode, true), [ds, columns, state.year, refCode])

  // CSV exporteert exact wat het scherm toont: zelfde modus, referentie en selectie (review #9)
  const exportCsv = () => {
    const header = [
      'Gebied',
      ...columns.map((c) => {
        const ind = indicatorById(ds, c.id)
        const suffix = relative && c.unit !== 'aantal' ? `, % t.o.v. ${referenceRow.name}` : ''
        return `${ind?.label ?? c.id} (${state.year}${suffix})`
      }),
    ]
    const body = [...refRows, ...rows].map((r) => [
      r.name,
      ...columns.map((c) => {
        const v = r.values[c.id]
        if (v == null) return ''
        if (relative && c.unit !== 'aantal') {
          const ref = referenceRow.values[c.id]
          if (ref == null || ref === 0) return ''
          return String(Math.round(((v - ref) / ref) * 1000) / 10).replace('.', ',')
        }
        return String(v).replace('.', ',')
      }),
    ])
    downloadCsv(
      `monitor-${ds.meta.gemeente}-${state.scope || 'gemeente'}-${theme.id}-${state.year}${relative ? '-relatief' : ''}.csv`,
      toCsv(header, body),
    )
  }

  return (
    <>
      <h1 className="view-title">Tabel — {state.year}</h1>
      <p className="view-sub">
        Alle indicatoren van een thema naast elkaar. Klik op een kolomkop om te sorteren; schakel naar{' '}
        <em>relatief</em> voor de afwijking t.o.v. {regionName(ds, ds.meta.gemeente)}.
      </p>

      <div className="filterbar" style={{ padding: '0 0 14px', maxWidth: 'none' }}>
        <label>Thema</label>
        <select
          className="control"
          value={theme.id}
          onChange={(e) => state.setThemeId(e.target.value)}
          aria-label="Thema"
        >
          {ds.themes.map((t) => (
            <option key={t.id} value={t.id}>
              {t.title}
            </option>
          ))}
        </select>

        <div className="seg" role="group" aria-label="Weergave">
          <button className={!relative ? 'active' : ''} onClick={() => setRelative(false)}>
            Absoluut
          </button>
          <button className={relative ? 'active' : ''} onClick={() => setRelative(true)}>
            Relatief
          </button>
        </div>

        {relative && state.scope && (
          <div className="seg" role="group" aria-label="Referentie">
            <button className={refChoice === 'gemeente' ? 'active' : ''} onClick={() => setRefChoice('gemeente')}>
              t.o.v. {regionName(ds, ds.meta.gemeente)}
            </button>
            <button className={refChoice === 'scope' ? 'active' : ''} onClick={() => setRefChoice('scope')}>
              t.o.v. {regionName(ds, state.scope)}
            </button>
          </div>
        )}

        <button className="control" onClick={exportCsv} style={{ backgroundImage: 'none' }}>
          ↓ Exporteer CSV
        </button>
      </div>

      <DataTable
        columns={columns}
        rows={rows}
        referenceRow={referenceRow}
        relative={relative}
        selected={state.selectedArea}
        onSelect={(c) => state.setSelectedArea(c === state.selectedArea ? null : c)}
      />

      <p className="view-sub" style={{ marginTop: 10 }}>
        Referentie: {referenceRow.name}{' '}
        {columns
          .map((c) => `${c.label} ${fmtValue(referenceRow.values[c.id], c.unit)}`)
          .slice(0, 3)
          .join(' · ')}{' '}
        · lege cellen: niet beschikbaar of door het CBS onderdrukt (kleine aantallen).
        {relative
          ? ' In relatieve weergave blijven absolute aantallen absoluut (grijs weergegeven) — een wijk indexeren op een totaal is niet zinvol.'
          : ''}
        {hasOutcomeCol ? ' * = gemodelleerde RIVM-schatting, geen directe telling.' : ''}
      </p>
    </>
  )
}
