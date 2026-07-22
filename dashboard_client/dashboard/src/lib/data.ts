import type { Dataset, Indicator, Region, RegionLevel } from '../types'

export const NL = 'NL00'

export function getValue(ds: Dataset, region: string, indicator: string, year: number): number | null {
  const yi = ds.years.indexOf(year)
  if (yi < 0) return null
  return ds.values[region]?.[indicator]?.[yi] ?? null
}

/** Reeks over alle jaren voor regio × indicator. */
export function getSeries(ds: Dataset, region: string, indicator: string): (number | null)[] {
  return ds.values[region]?.[indicator] ?? ds.years.map(() => null)
}

/** Verandering van eerste beschikbare jaar t/m het gekozen peiljaar (review #15:
 *  de trenddelta mag niet stil voorbij het gekozen jaar lopen). */
export function deltaOverPeriod(
  ds: Dataset,
  region: string,
  indicator: string,
  endYear?: number,
): { delta: number | null; fromYear: number | null; toYear: number | null } {
  const s = getSeries(ds, region, indicator)
  const maxIdx = endYear != null ? ds.years.indexOf(endYear) : ds.years.length - 1
  const idx = s
    .map((v, i) => (v != null && i <= (maxIdx < 0 ? ds.years.length - 1 : maxIdx) ? i : -1))
    .filter((i) => i >= 0)
  if (idx.length < 2) return { delta: null, fromYear: null, toYear: null }
  const first = idx[0]
  const last = idx[idx.length - 1]
  return { delta: s[last]! - s[first]!, fromYear: ds.years[first], toYear: ds.years[last] }
}

/** Jaren waarin de indicator daadwerkelijk data heeft voor deze gebiedsselectie
 *  (review #2: beschikbaarheid per scope × niveau, niet gemeentebreed). */
export function availableYears(ds: Dataset, list: Region[], indicator: string): number[] {
  if (list.length === 0) return []
  const need = Math.max(1, Math.ceil(0.5 * list.length))
  return ds.years.filter((_, yi) => {
    let filled = 0
    for (const a of list) if (ds.values[a.code]?.[indicator]?.[yi] != null) filled++
    return filled >= need
  })
}

/** Uitleg waaróm een gebied geen waarde heeft voor een indicator/jaar: welke
 *  data ontbreekt om de weergave te maken. Onderscheidt de verschillende
 *  oorzaken (datacatalogus-regel: leeg ≠ nul). */
export function noDataReason(
  ds: Dataset,
  code: string,
  indicator: Indicator,
  year: number,
): string {
  const region = ds.regions.find((r) => r.code === code)
  const level = region?.level
  const gebied = region?.name ?? code
  const avail = indicator.years
  // 1. indicator bestaat wel, maar niet in dit jaar
  if (!avail.includes(year)) {
    const nearest = avail.length
      ? avail.reduce((b, y) => (Math.abs(y - year) < Math.abs(b - year) ? y : b))
      : null
    if (indicator.isOutcome)
      return `RIVM meet ${indicator.shortLabel.toLowerCase()} niet in ${year}` +
        (nearest ? ` (wel in ${avail.join(', ')})` : '')
    return `${indicator.shortLabel} is niet beschikbaar voor ${year}` +
      (nearest ? ` — dichtstbijzijnde jaar: ${nearest}` : '')
  }
  // 2. jaar bestaat, maar dit specifieke gebied heeft geen waarde
  if (indicator.isOutcome)
    return `Geen RIVM-schatting voor ${gebied} in ${year} — de gemodelleerde ` +
      `kleine-gebiedsschatting ontbreekt of is voor deze ${level ?? 'gebied'} onderdrukt`
  if (level === 'buurt')
    return `Het CBS publiceert ${indicator.shortLabel.toLowerCase()} niet voor deze buurt ` +
      `in ${year} (onderdrukt wegens klein aantal, of alleen op wijkniveau gemeten)`
  return `Geen ${indicator.shortLabel.toLowerCase()} voor ${gebied} in ${year} ` +
    `(door het CBS onderdrukt of niet gemeten)`
}

/** Jaren waarin de dekking van een stadsdeel/gebied-aggregaat merkbaar sprong
 *  t.o.v. het voorgaande jaar (H1: bijv. Amsterdam-West 2022->2023, waar
 *  naamkoppeling na de herindeling tijdelijk brak). Zo'n sprong in het aantal
 *  meetellende wijken kan een nepverandering in absolute totalen veroorzaken. */
export function coverageBreakYears(ds: Dataset, code: string): number[] {
  const region = ds.regions.find((r) => r.code === code)
  const cov = region?.covFrac
  if (!cov) return []
  const out: number[] = []
  for (let i = 1; i < cov.length; i++) {
    const prev = cov[i - 1]
    const cur = cov[i]
    if (prev == null || cur == null) continue
    if (Math.abs(cur - prev) >= 0.15) out.push(ds.years[i])
  }
  return out
}

/** Dekkingsfractie (aandeel meetellende wijken) van een aggregaat in één jaar.
 *  < 1 betekent dat het totaal is opgebouwd uit onvolledige wijkdekking en de
 *  echte waarde onderschat — relevant voor enkeljaars-snapshots (H1). null voor
 *  wijk/buurt (geen aggregaat) of wanneer geen dekkingsinfo bekend is. */
export function coverageFrac(ds: Dataset, code: string, year: number): number | null {
  const region = ds.regions.find((r) => r.code === code)
  const cov = region?.covFrac
  if (!cov) return null
  const i = ds.years.indexOf(year)
  return i >= 0 ? cov[i] ?? null : null
}

/** Sorteerwaarde volgens de richting van de indicator: bij 'laag' is een lage
 *  waarde het sterkste signaal, dus sorteren we oplopend (review #3). */
export function signalSort(direction: 'hoog' | 'laag' | 'neutraal') {
  return (a: number | null, b: number | null): number => {
    if (a == null && b == null) return 0
    if (a == null) return 1
    if (b == null) return -1
    return direction === 'laag' ? a - b : b - a
  }
}

export function regionsOf(ds: Dataset, level: RegionLevel): Region[] {
  return ds.regions.filter((r) => r.level === level)
}

/** Valt regio r binnen scope (stadsdeel-/gebied-/gemeentecode)? '' = hele gemeente. */
export function inScope(r: Region, scope: string): boolean {
  if (!scope) return true
  return r.code === scope || r.sd === scope || r.gb === scope
}

/** Gebieden op `level` binnen `scope`, het analysekader van alle views. */
export function areas(ds: Dataset, level: RegionLevel, scope: string): Region[] {
  return regionsOf(ds, level).filter((r) => inScope(r, scope))
}

/** Niveaus die binnen deze scope zinvol zijn (grof -> fijn). */
export function levelsForScope(ds: Dataset, scope: string): RegionLevel[] {
  const scopeRegion = ds.regions.find((r) => r.code === scope)
  const all: RegionLevel[] = ['stadsdeel', 'gebied', 'wijk', 'buurt']
  return all.filter((lv) => {
    if (regionsOf(ds, lv).length === 0) return false
    if (!scopeRegion) return true // hele gemeente
    if (scopeRegion.level === 'stadsdeel') return lv === 'gebied' || lv === 'wijk' || lv === 'buurt'
    if (scopeRegion.level === 'gebied') return lv === 'wijk' || lv === 'buurt'
    return true
  })
}

export function indicatorById(ds: Dataset, id: string): Indicator | undefined {
  return ds.indicators.find((i) => i.id === id)
}

export function regionName(ds: Dataset, code: string): string {
  return ds.regions.find((r) => r.code === code)?.name ?? code
}

/** Dichtstbijzijnde jaargang waarin de indicator beschikbaar is. */
export function nearestYear(available: number[], target: number): number {
  if (available.length === 0) return target
  if (available.includes(target)) return target
  return available.reduce((best, y) =>
    Math.abs(y - target) < Math.abs(best - target) ? y : best,
  )
}

/** CSV-export (puntkomma, NL-Excel-vriendelijk). */
export function toCsv(header: string[], rows: (string | number | null)[][]): string {
  const esc = (v: string | number | null) => {
    if (v == null) return ''
    const s = String(v).replace(/"/g, '""')
    return /[;"\n]/.test(s) ? `"${s}"` : s
  }
  return [header, ...rows].map((r) => r.map(esc).join(';')).join('\r\n')
}

export function downloadCsv(filename: string, csv: string) {
  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
