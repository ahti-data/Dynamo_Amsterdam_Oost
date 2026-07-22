import type { Dataset, GentConfig, Region } from '../types'
import { getValue } from './data'

export interface GentComponentResult {
  id: string
  label: string
  /** ruwe verandering van het gebied over de periode (pct of pp) */
  change: number | null
  /** gestandaardiseerde, op gentrificatie-richting getekende score (z × sign) */
  z: number | null
}

export interface GentResult {
  code: string
  name: string
  /** samengestelde index = gemiddelde van beschikbare component-z-scores */
  index: number | null
  /** aantal beschikbare componenten (van het totaal) */
  coverage: number
  components: Record<string, GentComponentResult>
  /** assen voor het kwadrantdiagram */
  wozChange: number | null // % WOZ-stijging
  liChange: number | null // procentpunt-verandering aandeel lage inkomens
}

function change(
  ds: Dataset,
  code: string,
  indicator: string,
  y0: number,
  y1: number,
  mode: 'pct' | 'pp',
): number | null {
  const a = getValue(ds, code, indicator, y0)
  const b = getValue(ds, code, indicator, y1)
  if (a == null || b == null) return null
  if (mode === 'pct') return a === 0 ? null : ((b - a) / a) * 100
  return b - a
}

/** Aantal componenten met ≥50% dekking in jaar y voor deze gebiedsset. */
function componentsInYear(ds: Dataset, cfg: GentConfig, list: Region[], y: number): number {
  const yi = ds.years.indexOf(y)
  const need = Math.max(1, Math.ceil(0.5 * list.length))
  return cfg.components.filter((c) => {
    let filled = 0
    for (const a of list) if (ds.values[a.code]?.[c.id]?.[yi] != null) filled++
    return filled >= need
  }).length
}

/** Jaren waarin genoeg gentrificatiecomponenten data hebben voor deze gebiedsset:
 *  minstens 2 van de 4 componenten met ≥50% dekking. Op buurtniveau is inkomen
 *  vaak onderdrukt — de index rekent dan met de overige (WOZ, sociale huur,
 *  lage inkomens), wat als coverage per gebied zichtbaar is. */
export function gentYears(ds: Dataset, cfg: GentConfig, list: Region[]): number[] {
  if (list.length === 0) return []
  return ds.years.filter((y) => componentsInYear(ds, cfg, list, y) >= 2)
}

/** Jaren met VOLLEDIGE dekking (alle componenten ≥50%). Gebruikt om de standaard-
 *  periode te kiezen zodat kaart én verdringingsscatter beide gevuld zijn. */
export function gentYearsFull(ds: Dataset, cfg: GentConfig, list: Region[]): number[] {
  if (list.length === 0) return []
  return ds.years.filter((y) => componentsInYear(ds, cfg, list, y) === cfg.components.length)
}

/**
 * Gentrificatie-index per gebied over [y0, y1], gestandaardiseerd t.o.v. de
 * overige gebieden op hetzelfde niveau. Positief = gentrificeert sneller dan
 * gemiddeld. Zie GENTRIFICATION-config in build_data.py voor de onderbouwing.
 */
export function computeGentrification(
  ds: Dataset,
  cfg: GentConfig,
  list: Region[],
  y0: number,
  y1: number,
): GentResult[] {
  // 1. ruwe verandering per gebied × component
  const raw = list.map((a) => {
    const comp: Record<string, number | null> = {}
    for (const c of cfg.components) comp[c.id] = change(ds, a.code, c.id, y0, y1, c.mode)
    return { region: a, comp }
  })

  // 2. gemiddelde + standaarddeviatie per component (over gebieden met waarde)
  const stats: Record<string, { mean: number; sd: number }> = {}
  for (const c of cfg.components) {
    const vals = raw.map((r) => r.comp[c.id]).filter((v): v is number => v != null)
    if (vals.length < 2) {
      stats[c.id] = { mean: NaN, sd: 0 }
      continue
    }
    const mean = vals.reduce((s, v) => s + v, 0) / vals.length
    const variance = vals.reduce((s, v) => s + (v - mean) ** 2, 0) / vals.length
    stats[c.id] = { mean, sd: Math.sqrt(variance) }
  }

  // 3. z-score × richting; index = gemiddelde van beschikbare componenten
  return raw.map(({ region, comp }) => {
    const components: Record<string, GentComponentResult> = {}
    const zs: number[] = []
    for (const c of cfg.components) {
      const raw0 = comp[c.id]
      const st = stats[c.id]
      let z: number | null = null
      if (raw0 != null && st.sd > 0 && !Number.isNaN(st.mean)) {
        z = ((raw0 - st.mean) / st.sd) * c.sign
        zs.push(z)
      }
      components[c.id] = { id: c.id, label: c.label, change: raw0, z }
    }
    const index = zs.length ? zs.reduce((s, v) => s + v, 0) / zs.length : null
    return {
      code: region.code,
      name: region.name,
      index,
      coverage: zs.length,
      components,
      wozChange: comp['g_wozbag'] ?? null,
      liChange: comp['p_hh_li'] ?? null,
    }
  })
}
