import type { Dataset, Region } from '../types'
import { getValue } from './data'

export interface Pair {
  code: string
  name: string
  x: number
  y: number
}

export interface CorrResult {
  r: number | null
  n: number
  pairs: Pair[]
  /** helling en intercept van de kleinste-kwadraten-trendlijn (y = a·x + b) */
  slope: number | null
  intercept: number | null
}

/** Pearson-correlatie tussen twee indicatoren over gebieden in `list`, jaar `year`. */
export function pearson(
  ds: Dataset,
  list: Region[],
  xId: string,
  yId: string,
  year: number,
): CorrResult {
  const pairs: Pair[] = []
  for (const a of list) {
    const x = getValue(ds, a.code, xId, year)
    const y = getValue(ds, a.code, yId, year)
    if (x == null || y == null || !Number.isFinite(x) || !Number.isFinite(y)) continue
    pairs.push({ code: a.code, name: a.name, x, y })
  }
  const n = pairs.length
  if (n < 3) return { r: null, n, pairs, slope: null, intercept: null }

  const mx = pairs.reduce((s, p) => s + p.x, 0) / n
  const my = pairs.reduce((s, p) => s + p.y, 0) / n
  let sxy = 0, sxx = 0, syy = 0
  for (const p of pairs) {
    const dx = p.x - mx
    const dy = p.y - my
    sxy += dx * dy
    sxx += dx * dx
    syy += dy * dy
  }
  if (sxx === 0 || syy === 0) return { r: null, n, pairs, slope: null, intercept: null }
  const r = sxy / Math.sqrt(sxx * syy)
  const slope = sxy / sxx
  const intercept = my - slope * mx
  return { r, n, pairs, slope, intercept }
}

/** Spearman-rangcorrelatie (robuust tegen uitschieters en niet-lineaire monotone verbanden). */
export function spearman(
  ds: Dataset,
  list: Region[],
  xId: string,
  yId: string,
  year: number,
): CorrResult {
  const base = pearson(ds, list, xId, yId, year)
  if (base.n < 3) return base
  const rank = (vals: number[]): number[] => {
    const idx = vals.map((v, i) => [v, i] as const).sort((a, b) => a[0] - b[0])
    const ranks = new Array(vals.length).fill(0)
    let i = 0
    while (i < idx.length) {
      let j = i
      while (j + 1 < idx.length && idx[j + 1][0] === idx[i][0]) j++
      const avg = (i + j) / 2 + 1 // gemiddelde rang bij gelijke waarden (1-based)
      for (let k = i; k <= j; k++) ranks[idx[k][1]] = avg
      i = j + 1
    }
    return ranks
  }
  const rx = rank(base.pairs.map((p) => p.x))
  const ry = rank(base.pairs.map((p) => p.y))
  const n = base.n
  const mx = (n + 1) / 2
  let sxy = 0, sxx = 0, syy = 0
  for (let i = 0; i < n; i++) {
    const dx = rx[i] - mx
    const dy = ry[i] - mx
    sxy += dx * dy
    sxx += dx * dx
    syy += dy * dy
  }
  const r = sxx === 0 || syy === 0 ? null : sxy / Math.sqrt(sxx * syy)
  // trendlijn blijft op de ruwe waarden (voor de scatter), rangcorrelatie alleen voor r
  return { r, n, pairs: base.pairs, slope: base.slope, intercept: base.intercept }
}

export type Method = 'pearson' | 'spearman'

export function correlate(
  ds: Dataset,
  list: Region[],
  xId: string,
  yId: string,
  year: number,
  method: Method,
): CorrResult {
  return method === 'spearman'
    ? spearman(ds, list, xId, yId, year)
    : pearson(ds, list, xId, yId, year)
}

/** 95%-betrouwbaarheidsinterval van r via Fisher-z-transformatie. Voor Spearman ρ
 *  gebruikt de standaardfout de correctie √(1.06/(n−3)) (Fieller), want de gewone
 *  Pearson-SE geeft een ~3% te smal interval (STAT-2). */
export function fisherCI(r: number | null, n: number, method: Method = 'pearson'): { lo: number; hi: number } | null {
  if (r == null || n < 4 || Math.abs(r) >= 1) return null
  const z = 0.5 * Math.log((1 + r) / (1 - r))
  const se = method === 'spearman' ? Math.sqrt(1.06 / (n - 3)) : 1 / Math.sqrt(n - 3)
  return { lo: Math.tanh(z - 1.96 * se), hi: Math.tanh(z + 1.96 * se) }
}

/** Kwalificatie van de sterkte (absolute r), met neutrale drempels. */
export function strength(r: number | null): string {
  if (r == null) return 'onvoldoende data'
  const a = Math.abs(r)
  if (a < 0.2) return 'verwaarloosbaar'
  if (a < 0.4) return 'zwak'
  if (a < 0.6) return 'matig'
  if (a < 0.8) return 'sterk'
  return 'zeer sterk'
}

/** Tweezijdige benaderde p-waarde via t-verdeling (t = r·√((n−2)/(1−r²))).
 *  Alleen als ruwe significantie-indicatie; de ecologische kanttekening blijft leidend. */
export function approxP(r: number | null, n: number): number | null {
  // bij perfecte collineariteit of te weinig punten geen (schijn)exacte p (STAT-5)
  if (r == null || n < 3 || Math.abs(r) >= 1) return null
  const t = Math.abs(r) * Math.sqrt((n - 2) / (1 - r * r))
  const df = n - 2
  // benadering van de staartkans van Student-t via een normale benadering met correctie
  const x = df / (df + t * t)
  // regularized incomplete beta benadering (Press et al., voldoende voor een indicatie)
  const betacf = ibeta(df / 2, 0.5, x)
  return Math.max(0, Math.min(1, betacf))
}

// regularized incomplete beta I_x(a,b) via continued fraction (Numerical Recipes)
function ibeta(a: number, b: number, x: number): number {
  if (x <= 0) return 0
  if (x >= 1) return 1
  const lnBeta = gammaln(a + b) - gammaln(a) - gammaln(b) + a * Math.log(x) + b * Math.log(1 - x)
  const front = Math.exp(lnBeta) / a
  let f = 1, c = 1, d = 0
  for (let i = 0; i <= 200; i++) {
    const m = Math.floor(i / 2)
    let num: number
    if (i === 0) num = 1
    else if (i % 2 === 0) num = (m * (b - m) * x) / ((a + 2 * m - 1) * (a + 2 * m))
    else num = -((a + m) * (a + b + m) * x) / ((a + 2 * m) * (a + 2 * m + 1))
    d = 1 + num * d
    if (Math.abs(d) < 1e-30) d = 1e-30
    d = 1 / d
    c = 1 + num / c
    if (Math.abs(c) < 1e-30) c = 1e-30
    const cd = c * d
    f *= cd
    if (Math.abs(1 - cd) < 1e-8) break
  }
  return front * (f - 1)
}

function gammaln(x: number): number {
  const c = [
    76.18009172947146, -86.50532032941677, 24.01409824083091,
    -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5,
  ]
  let y = x
  let tmp = x + 5.5
  tmp -= (x + 0.5) * Math.log(tmp)
  let ser = 1.000000000190015
  for (let j = 0; j < 6; j++) ser += c[j] / ++y
  return -tmp + Math.log((2.5066282746310002 * ser) / x)
}
