import type { Unit } from '../types'

const nfInt = new Intl.NumberFormat('nl-NL', { maximumFractionDigits: 0 })
const nf1 = new Intl.NumberFormat('nl-NL', { minimumFractionDigits: 1, maximumFractionDigits: 1 })
const nfEuro = new Intl.NumberFormat('nl-NL', {
  style: 'currency',
  currency: 'EUR',
  maximumFractionDigits: 0,
})

/** Waarde met eenheid, Nederlandse notatie. */
export function fmtValue(v: number | null | undefined, unit: Unit): string {
  if (v == null || Number.isNaN(v)) return '–'
  switch (unit) {
    case 'pct':
      return `${Number.isInteger(v) ? nfInt.format(v) : nf1.format(v)}%`
    case 'euro':
      return nfEuro.format(v)
    case 'per_km2':
      return `${nfInt.format(v)}/km²`
    case 'per_1000':
      return `${nf1.format(v)}‰`
    case 'km':
      return `${nf1.format(v)} km`
    case 'personen':
      return nf1.format(v)
    case 'index':
      return nf1.format(v)
    default:
      return nfInt.format(v)
  }
}

/** Compacte weergave voor astitels en tegels: 12,4k / 1,2 mln. */
export function fmtCompact(v: number | null | undefined, unit: Unit): string {
  if (v == null || Number.isNaN(v)) return '–'
  if (unit === 'pct' || unit === 'per_1000' || unit === 'km' || unit === 'personen')
    return fmtValue(v, unit)
  if (unit === 'euro') {
    if (Math.abs(v) >= 1000) return `€ ${nf1.format(v / 1000)}k`
    return nfEuro.format(v)
  }
  const a = Math.abs(v)
  if (a >= 1_000_000) return `${nf1.format(v / 1_000_000)} mln`
  if (a >= 10_000) return `${nf1.format(v / 1000)}k`
  return nfInt.format(v)
}

/** Verschil met teken; pp voor percentages. */
const nf2 = new Intl.NumberFormat('nl-NL', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

export function fmtDelta(v: number | null | undefined, unit: Unit): string {
  if (v == null || Number.isNaN(v)) return '–'
  const sign = v > 0 ? '+' : ''
  if (unit === 'pct') return `${sign}${nf1.format(v)} pp`
  if (unit === 'euro') return `${sign}${nfEuro.format(v)}`
  if (unit === 'personen' || unit === 'km') return `${sign}${nf2.format(v)}`
  if (unit === 'per_1000') return `${sign}${nf1.format(v)}‰`
  const a = Math.abs(v)
  const body = a >= 10_000 ? `${nf1.format(v / 1000)}k` : nfInt.format(v)
  return `${sign}${body}`
}

/** Relatieve afwijking t.o.v. referentie in %, met teken. */
export function fmtRelative(v: number | null, ref: number | null): string {
  if (v == null || ref == null || ref === 0) return '–'
  const d = ((v - ref) / ref) * 100
  const sign = d > 0 ? '+' : ''
  return `${sign}${nf1.format(d)}%`
}

/** Compacte as-tick met eenheid en nl-NL-notatie (L8: voorheen ontbrak de
 *  eenheid bij euro/promille/km/index en gebruikte pct een Engelse punt). */
export function fmtTick(t: number, unit: Unit): string {
  if (unit === 'pct') return `${nfInt.format(t)}%`
  if (unit === 'euro') return Math.abs(t) >= 1000 ? `€ ${nf1.format(t / 1000)}k` : nfEuro.format(t)
  if (unit === 'per_km2') return `${nfInt.format(t)}/km²`
  if (unit === 'per_1000') return `${nf1.format(t)}‰`
  if (unit === 'km') return `${nf1.format(t)} km`
  if (unit === 'index') return nf1.format(t)
  if (Math.abs(t) >= 1000) return `${nf1.format(t / 1000)}k`
  return nfInt.format(t)
}

/** Nette astick-waarden (0 / 1.000 / 2.000). */
export function niceTicks(min: number, max: number, count = 4): number[] {
  if (max === min) max = min + 1
  const span = max - min
  const step0 = span / count
  const mag = Math.pow(10, Math.floor(Math.log10(step0)))
  const norm = step0 / mag
  const step = (norm >= 5 ? 10 : norm >= 2.5 ? 5 : norm >= 1.5 ? 2 : 1) * mag
  const start = Math.ceil(min / step) * step
  const ticks: number[] = []
  for (let t = start; t <= max + step * 0.001; t += step) ticks.push(Math.round(t * 1e6) / 1e6)
  return ticks
}
