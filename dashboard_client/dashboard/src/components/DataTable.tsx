import { useMemo, useState } from 'react'
import type { Unit } from '../types'
import { fmtValue, fmtRelative } from '../lib/format'

export interface TableColumn {
  id: string
  label: string
  unit: Unit
}

export interface TableRowData {
  code: string
  name: string
  values: Record<string, number | null>
  reference?: boolean
}

interface Props {
  columns: TableColumn[]
  rows: TableRowData[]
  /** referentierij voor relatieve weergave (bijv. Amsterdam) */
  referenceRow?: TableRowData
  relative?: boolean
  onSelect?: (code: string) => void
  selected?: string | null
}

type Sort = { col: string; dir: 1 | -1 }

export function DataTable({ columns, rows, referenceRow, relative = false, onSelect, selected }: Props) {
  const [sort, setSort] = useState<Sort>({ col: 'name', dir: 1 })

  const sorted = useMemo(() => {
    const arr = [...rows]
    arr.sort((a, b) => {
      // referentierijen (bijv. Oost-totaal) blijven bovenaan staan
      if (!!a.reference !== !!b.reference) return a.reference ? -1 : 1
      if (sort.col === 'name') return a.name.localeCompare(b.name, 'nl') * sort.dir
      const av = a.values[sort.col]
      const bv = b.values[sort.col]
      if (av == null && bv == null) return 0
      if (av == null) return 1
      if (bv == null) return -1
      return (av - bv) * sort.dir
    })
    return arr
  }, [rows, sort])

  const toggle = (col: string) =>
    setSort((s) => (s.col === col ? { col, dir: s.dir === 1 ? -1 : 1 } : { col, dir: col === 'name' ? 1 : -1 }))

  const arrow = (col: string) => (sort.col === col ? (sort.dir === 1 ? ' ↑' : ' ↓') : '')

  return (
    <div className="table-scroll">
      <table className="data-table">
        <thead>
          <tr>
            <th className="sticky-col">
              <button onClick={() => toggle('name')}>Gebied{arrow('name')}</button>
            </th>
            {columns.map((c) => (
              <th key={c.id}>
                <button onClick={() => toggle(c.id)} title={c.label}>
                  {c.label}
                  {arrow(c.id)}
                </button>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {referenceRow && (
            <tr className="ref-row">
              <td className="sticky-col">{referenceRow.name}</td>
              {columns.map((c) => (
                <td key={c.id}>{fmtValue(referenceRow.values[c.id], c.unit)}</td>
              ))}
            </tr>
          )}
          {sorted.map((r) => (
            <tr
              key={r.code}
              className={`${r.reference ? 'ref-row' : ''}${selected === r.code ? ' selected' : ''}${onSelect ? ' clickable' : ''}`}
              onClick={onSelect ? () => onSelect(r.code) : undefined}
              tabIndex={onSelect ? 0 : undefined}
              onKeyDown={
                onSelect
                  ? (e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault()
                        onSelect(r.code)
                      }
                    }
                  : undefined
              }
            >
              <td className="sticky-col">{r.name}</td>
              {columns.map((c) => {
                const v = r.values[c.id]
                // absolute aantallen nooit als procentuele afwijking tonen (review #9)
                if (!relative || !referenceRow || c.unit === 'aantal') {
                  return (
                    <td key={c.id} className={relative && c.unit === 'aantal' ? 'abs-in-rel' : ''}>
                      {fmtValue(v, c.unit)}
                    </td>
                  )
                }
                const ref = referenceRow.values[c.id]
                const rel = v != null && ref != null && ref !== 0 ? (v - ref) / ref : null
                return (
                  <td key={c.id} className={rel == null ? '' : rel > 0.001 ? 'rel-up' : rel < -0.001 ? 'rel-down' : ''}>
                    {fmtRelative(v, ref ?? null)}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
