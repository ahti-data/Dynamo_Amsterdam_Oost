import type { Dataset, Region } from '../types'
import { getSeries } from './data'

/* ============================================================================
 * Prognose voor Dynamo-doelgroepen op laag geografisch niveau.
 *
 * Tot augustus 2026 deed dit bestand zelf een log-lineaire trendextrapolatie
 * (met shrinkage, demping en top-down raking — zie git-historie en
 * docs/VOORUITBLIK-TEAM.md §3 voor de oude methode). Die is verwijderd: hij
 * was een eigen model zonder demografische drivers (geen vitale statistiek,
 * geen woningbouwpijplijn) dat overal een getal liet zien, ook waar dat getal
 * weinig voorstelde. Sindsdien toont deze tool **uitsluitend echte officiële
 * puntprognoses** (gemeente Amsterdam O&S / BBGA) waar die bestaan, en
 * expliciet "geen officiële prognose beschikbaar" waar niet — zie
 * docs/VOORUITBLIK-TEAM.md §6 en data-prep/official_forecast.py.
 *
 * Dekking is daardoor beperkt en ongelijk: a_inw/a_65_oo bestaan voor heel
 * Amsterdam (gemeente/stadsdeel/gebied/wijk, via BBGA), a_00_14/a_15_24/
 * a_45_64 alleen voor stadsdeel Oost + zijn wijken (O&S-Excel). a_1p_hh en
 * a_hh, elke buurt, en elke andere gemeente hebben nergens een officiële
 * bron — daar is dus nooit een prognosepunt.
 * ========================================================================== */

/** Jaren waarvoor een van de officiële bronnen een prognose publiceert. */
export const HORIZONS = [2026, 2030, 2035, 2040, 2050, 2055] as const

export interface ForecastPoint {
  year: number
  value: number
  /** true = officiële prognose, false = waarneming. Geen onzekerheidsband: de
   *  bronnen (O&S/BBGA) publiceren geen interval, dus alleen een puntwaarde. */
  forecast: boolean
}

export interface AreaForecast {
  code: string
  /** waarnemingen uitgelijnd op ds.years (null = ontbreekt) */
  history: (number | null)[]
  /** waarnemings- én officiële prognosepunten (alleen jaren met een bron) */
  points: ForecastPoint[]
  lastObsYear: number
  lastObsValue: number
  /** officiële prognosewaarde per horizonjaar waarvoor die bestaat */
  projected: Record<number, number>
}

/** Laatste niet-lege waarneming uit een reeks; null als er geen is. */
function lastObservation(years: number[], series: (number | null)[]): { year: number; value: number } | null {
  for (let i = years.length - 1; i >= 0; i--) {
    const v = series[i]
    if (v != null && Number.isFinite(v)) return { year: years[i], value: v }
  }
  return null
}

/** Prognose voor één gebied: waarneming + officiële punten waar die bestaan. */
export function forecastArea(ds: Dataset, indicator: string, code: string): AreaForecast | null {
  const region = ds.regions.find((r) => r.code === code)
  if (!region) return null
  const history = getSeries(ds, code, indicator)
  const last = lastObservation(ds.years, history)
  if (!last) return null
  const lastYear = ds.years[ds.years.length - 1]

  const points: ForecastPoint[] = []
  ds.years.forEach((y, i) => {
    const v = history[i]
    if (v != null) points.push({ year: y, value: v, forecast: false })
  })

  const projected: Record<number, number> = {}
  for (const y of HORIZONS) {
    if (y <= lastYear) continue
    const official = ds.officialForecast?.[code]?.[indicator]?.[y]
    if (official == null) continue // géén trendvangnet: geen bron = geen punt
    points.push({ year: y, value: official, forecast: true })
    projected[y] = official
  }

  return { code, history, points, lastObsYear: last.year, lastObsValue: last.value, projected }
}

/** Prognose voor elk gebied in `areas` dat een waarneming heeft. */
export function forecastGroup(ds: Dataset, indicator: string, areas: Region[]): Map<string, AreaForecast> {
  const out = new Map<string, AreaForecast>()
  for (const r of areas) {
    const f = forecastArea(ds, indicator, r.code)
    if (f) out.set(r.code, f)
  }
  return out
}

/** Relatieve verandering (%) tussen laatste waarneming en horizonjaar; null als er voor dat jaar geen officiële prognose is. */
export function pctChange(f: AreaForecast, toYear: number): number | null {
  const v = f.projected[toYear]
  if (v == null || !f.lastObsValue) return null
  return ((v - f.lastObsValue) / f.lastObsValue) * 100
}

/** Absolute verandering tussen laatste waarneming en horizonjaar; null als er voor dat jaar geen officiële prognose is. */
export function absChange(f: AreaForecast, toYear: number): number | null {
  const v = f.projected[toYear]
  if (v == null) return null
  return v - f.lastObsValue
}
