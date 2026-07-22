import type { Dataset, Region } from '../types'
import { getSeries } from './data'

/* ============================================================================
 * Prognose-engine voor Dynamo-doelgroepen op laag geografisch niveau.
 *
 * Methode (zie docs/VOORUITBLIK-TEAM.md): trendextrapolatie in log-ruimte, met
 *   (1) shrinkage van de groeivoet naar het bovenliggende gebied (ruis van
 *       kleine gebieden temmen — composiet-/James-Stein-idee),
 *   (2) demping van de groeivoet over de horizon (groei zet niet oneindig door),
 *   (3) top-down raking zodat sub-gebieden optellen tot het bovenliggende
 *       gebied (consistentie), en
 *   (4) een onzekerheidsband uit de historische trendresiduen.
 *
 * Zuivere cohort-component of Hamilton–Perry is bewust NIET gebruikt: de CBS-
 * leeftijdsklassen (0–14, 15–24, 45–64, 65+) zijn ongelijk van breedte en
 * sluiten niet op een projectiestap aan, en vitale statistieken (geboorte/
 * sterfte/migratie) ontbreken op buurtniveau. Zie AANNAMES.
 * ========================================================================== */

/** Aantal jaren dat we vooruit projecteren t.o.v. het laatste waarnemingsjaar. */
export const HORIZONS = [2030, 2035] as const

/** Groeivoet begrenzen: kleine gebieden geven snel onrealistische extrapolaties.
 *  GROWTH_CAP is de "knie": tot ±6%/jr blijft de trend onaangetast; daarboven wordt
 *  de groeivoet glad gecomprimeerd naar een absoluut plafond RATE_CEIL (±9%/jr) in
 *  plaats van hard afgekapt. Een harde knip op 6% maakte álle snelle groeiers exact
 *  gelijk (nieuwbouwwijken als IJburg/Zeeburgereiland kwamen allemaal op +47,9% uit),
 *  omdat de %-verandering alleen van de groeivoet afhangt. Met de gladde compressie
 *  houdt elke wijk een eigen, onderscheiden prognose terwijl extreme extrapolaties
 *  (bv. +22%/jr) nog steeds getemd worden. */
const GROWTH_CAP = 0.06 // knie op ±6% per jaar
/** Absoluut plafond waarnaar de groeivoet verzadigt (nooit overschreden). */
const RATE_CEIL = GROWTH_CAP * 1.5 // ±9% per jaar
/** Dempingsfactor: elke stap verder telt de groeivoet zwakker mee. */
const DAMPING = 0.9
/** Minimale (relatieve) trendruis, zodat de band nooit schijnzeker smal wordt. */
const SIGMA_FLOOR = 0.015
/** Maximale (relatieve) trendruis: CBS-afronding op vijftallen geeft bij kleine
 *  tellingen enorme log-residuen; zonder plafond kan de band de hele fan chart
 *  platdrukken of een negatieve ondergrens opleveren (H2). */
const SIGMA_CAP = 0.25
/** Minimaal aantal waarnemingen voor een eigen trend; anders leunen op parent. */
const MIN_POINTS = 4

export interface ForecastPoint {
  year: number
  value: number
  lo: number
  hi: number
  /** true = geprognosticeerd jaar, false = waarneming */
  forecast: boolean
}

export interface AreaForecast {
  code: string
  /** waarnemingen uitgelijnd op ds.years (null = ontbreekt) */
  history: (number | null)[]
  /** waarnemings- én prognosepunten met onzekerheidsband */
  points: ForecastPoint[]
  /** gemengde, gedempte jaarlijkse groeivoet die is toegepast */
  rate: number
  /** aandeel eigen trend in de gemengde groeivoet (1 = volledig eigen) */
  ownWeight: number
  /** true = de trend lag boven het plafond en is glad gecomprimeerd (prognose is
   *  een getemde ondergrens; de werkelijke aanwas kan hoger liggen) */
  compressed: boolean
  lastObsYear: number
  lastObsValue: number
  /** geprognosticeerde waarde per horizonjaar (na raking) */
  projected: Record<number, number>
}

interface Fit {
  /** jaarlijkse groeivoet uit de log-lineaire trend */
  rate: number
  /** relatieve trendruis (std van residuen in log-ruimte) */
  sigma: number
  /** aantal gebruikte waarnemingen */
  n: number
  lastYear: number
  lastValue: number
}

/** Log-lineaire trendfit; valt terug op lineair als er niet-positieve waarden zijn. */
function fitTrend(years: number[], series: (number | null)[]): Fit | null {
  const obs: { t: number; v: number }[] = []
  years.forEach((y, i) => {
    const v = series[i]
    if (v != null && Number.isFinite(v)) obs.push({ t: y, v })
  })
  if (obs.length < 2) return null
  const usable = obs.slice(-10) // hooguit de laatste 10 jaren
  const n = usable.length
  const useLog = usable.every((o) => o.v > 0)
  const xs = usable.map((o) => o.t)
  const ys = usable.map((o) => (useLog ? Math.log(o.v) : o.v))
  const mx = xs.reduce((a, b) => a + b, 0) / n
  const my = ys.reduce((a, b) => a + b, 0) / n
  let sxx = 0
  let sxy = 0
  for (let i = 0; i < n; i++) {
    sxx += (xs[i] - mx) ** 2
    sxy += (xs[i] - mx) * (ys[i] - my)
  }
  const b = sxx ? sxy / sxx : 0
  const a = my - b * mx
  let ss = 0
  for (let i = 0; i < n; i++) ss += (ys[i] - (a + b * xs[i])) ** 2
  const resStd = n > 2 ? Math.sqrt(ss / (n - 2)) : 0
  const lastValue = usable[n - 1].v
  const rate = useLog ? Math.exp(b) - 1 : lastValue ? b / lastValue : 0
  const sigma = useLog ? resStd : lastValue ? resStd / Math.abs(lastValue) : 0
  return { rate, sigma, n, lastYear: usable[n - 1].t, lastValue }
}

/** Bovenliggend gebied (parent) voor top-down consistentie en shrinkage. */
export function parentCode(ds: Dataset, r: Region): string {
  const has = (c?: string) => !!c && !!ds.values[c]
  if (r.level === 'buurt') {
    if (has(r.wk)) return r.wk!
    if (has(r.gb)) return r.gb!
    if (has(r.sd)) return r.sd!
  } else if (r.level === 'wijk') {
    if (has(r.gb)) return r.gb!
    if (has(r.sd)) return r.sd!
  } else if (r.level === 'gebied' || r.level === 'stadsdeel') {
    if (has(r.sd) && r.sd !== r.code) return r.sd!
  }
  return ds.meta.gemeente
}

/** Damping-gecorrigeerde cumulatieve groeifactor over `h` stappen. */
function grow(v0: number, rate: number, h: number): number {
  let v = v0
  for (let k = 0; k < h; k++) v *= 1 + rate * DAMPING ** k
  return v
}

interface RawForecast {
  code: string
  history: (number | null)[]
  fit: Fit
  rate: number
  ownWeight: number
  /** true = de trend liep boven de knie en is glad gecomprimeerd */
  compressed: boolean
}

/**
 * Prognose voor één indicator, voor een set gebieden op één niveau, met
 * shrinkage naar de parent en (optioneel) top-down raking naar een ankergebied.
 *
 * @param anchor code van het gebied waarnaar de som van `areas` wordt gerakt
 *   (bijv. de gekozen scope). null = geen raking (elk gebied op eigen trend).
 */
export function forecastGroup(
  ds: Dataset,
  indicator: string,
  areas: Region[],
  anchor: string | null,
): Map<string, AreaForecast> {
  const lastYear = ds.years[ds.years.length - 1]
  const targetYears = [...ds.years, ...HORIZONS.filter((y) => y > lastYear)]

  // referentie-groeivoet per parent (voor shrinkage) — één keer fitten
  const parentFit = new Map<string, Fit | null>()
  const fitFor = (code: string): Fit | null => {
    if (!parentFit.has(code)) parentFit.set(code, fitTrend(ds.years, getSeries(ds, code, indicator)))
    return parentFit.get(code)!
  }

  // mediane omvang op dit niveau — schaalvrije shrinkage-constante K
  const sizes = areas
    .map((r) => fitTrend(ds.years, getSeries(ds, r.code, indicator))?.lastValue)
    .filter((v): v is number => v != null && v > 0)
    .sort((a, b) => a - b)
  const medianSize = sizes.length ? sizes[Math.floor(sizes.length / 2)] : 1
  const K = Math.max(medianSize, 1)

  const raw: RawForecast[] = []
  for (const r of areas) {
    const history = getSeries(ds, r.code, indicator)
    const fit = fitTrend(ds.years, history)
    if (!fit) continue
    const pCode = parentCode(ds, r)
    const pFit = fitFor(pCode)
    const parentRate = pFit ? pFit.rate : fit.rate
    // shrinkage van de groeivoet: kleine/korte reeksen leunen op de parent
    const sizeW = fit.lastValue / (fit.lastValue + K)
    const dataW = Math.min(1, (fit.n - 1) / (MIN_POINTS - 1))
    const ownWeight = Math.max(0, Math.min(1, sizeW * dataW))
    const blended = ownWeight * fit.rate + (1 - ownWeight) * parentRate
    const rate = softCap(blended)
    raw.push({ code: r.code, history, fit, rate, ownWeight, compressed: isCompressed(blended) })
  }

  // top-down raking: schaal de sub-gebieden zodat hun som het ankergebied volgt
  const anchorFit = anchor ? fitFor(anchor) : null
  const rakeFactor = new Map<number, number>() // per prognosejaar
  if (anchor && anchorFit) {
    for (const y of targetYears) {
      if (y <= lastYear) continue
      const h = y - anchorFit.lastYear
      const anchorProj = grow(anchorFit.lastValue, softCap(anchorFit.rate), h)
      const sumChildren = raw.reduce((s, rf) => s + grow(rf.fit.lastValue, rf.rate, y - rf.fit.lastYear), 0)
      rakeFactor.set(y, sumChildren > 0 ? anchorProj / sumChildren : 1)
    }
  }

  const out = new Map<string, AreaForecast>()
  for (const rf of raw) {
    const points: ForecastPoint[] = []
    // waarnemingen
    ds.years.forEach((y, i) => {
      const v = rf.history[i]
      if (v != null) points.push({ year: y, value: v, lo: v, hi: v, forecast: false })
    })
    const projected: Record<number, number> = {}
    for (const y of targetYears) {
      if (y <= lastYear) continue
      const h = y - rf.fit.lastYear
      let value = grow(rf.fit.lastValue, rf.rate, h)
      const rk = rakeFactor.get(y)
      if (rk != null) value *= rk
      // onzekerheidsband: groeit met √horizon; ruimer bij meer shrinkage; gekapt (H2)
      const sigmaEff = Math.min(
        Math.max(rf.fit.sigma, SIGMA_FLOOR) + (1 - rf.ownWeight) * 0.01,
        SIGMA_CAP,
      )
      // log-symmetrische band i.p.v. value*(1±spread): die laatste wordt negatief
      // zodra spread > 1 (onmogelijke waarde voor een aantal/percentage)
      const band = sigmaEff * Math.sqrt(h)
      points.push({
        year: y,
        value,
        lo: value * Math.exp(-band),
        hi: value * Math.exp(band),
        forecast: true,
      })
      projected[y] = value
    }
    out.set(rf.code, {
      code: rf.code,
      history: rf.history,
      points,
      rate: rf.rate,
      ownWeight: rf.ownWeight,
      compressed: rf.compressed,
      lastObsYear: rf.fit.lastYear,
      lastObsValue: rf.fit.lastValue,
      projected,
    })
  }
  return out
}

/** Gladde begrenzing van de groeivoet: identiteit tot de knie (±GROWTH_CAP), daarboven
 *  smooth verzadigend naar ±RATE_CEIL. Monotoon, dus de rangorde blijft behouden en
 *  twee verschillende snelle groeiers krijgen niet langer exact dezelfde prognose. */
function softCap(r: number): number {
  const a = Math.abs(r)
  if (a <= GROWTH_CAP) return r
  const room = RATE_CEIL - GROWTH_CAP
  return Math.sign(r) * (GROWTH_CAP + room * Math.tanh((a - GROWTH_CAP) / room))
}

/** true zodra de gladde compressie daadwerkelijk ingrijpt (|rate| > knie). */
function isCompressed(r: number): boolean {
  return Math.abs(r) > GROWTH_CAP
}

/** Prognose voor één gebied (bijv. de scope) zonder raking — voor de fan chart. */
export function forecastArea(ds: Dataset, indicator: string, code: string): AreaForecast | null {
  const r = ds.regions.find((x) => x.code === code)
  if (!r) return null
  const m = forecastGroup(ds, indicator, [r], null)
  return m.get(code) ?? null
}

/** Relatieve verandering (%) tussen laatste waarneming en horizonjaar. */
export function pctChange(f: AreaForecast, toYear: number): number | null {
  const v = f.projected[toYear]
  if (v == null || !f.lastObsValue) return null
  return ((v - f.lastObsValue) / f.lastObsValue) * 100
}

/** Absolute verandering tussen laatste waarneming en horizonjaar. */
export function absChange(f: AreaForecast, toYear: number): number | null {
  const v = f.projected[toYear]
  if (v == null) return null
  return v - f.lastObsValue
}
