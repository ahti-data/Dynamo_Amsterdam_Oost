/** Datamodel van de monitor. Gegenereerd door data-prep/build_data.py. */

export type RegionLevel = 'buurt' | 'wijk' | 'gebied' | 'stadsdeel' | 'gemeente' | 'land'

export interface Region {
  code: string
  name: string
  level: RegionLevel
  /** stadsdeel-aggregaatcode (alleen Amsterdam), bijv. SD-M */
  sd?: string
  /** gebied-aggregaatcode (alleen Amsterdam), bijv. GB-DX03 */
  gb?: string
  /** wijkcode waar deze buurt onder valt */
  wk?: string
  /** aantal onderliggende wijken van dit aggregaat (dekking) */
  members?: number
  /** dekkingsgraad per jaar (aandeel wijken met een waarde), alleen voor
   *  stadsdeel/gebied-aggregaten. Een sprong in dekking tussen twee jaren
   *  (bijv. door een herindeling die naamkoppeling tijdelijk breekt) kan een
   *  nepverandering in de tijdreeks veroorzaken (H1) — zie coverageBreakYears. */
  covFrac?: (number | null)[]
}

/** Richting van een indicator t.o.v. ondersteuningsbehoefte:
 *  hoog = hogere waarde is sterker signaal; laag = lagere waarde is sterker
 *  signaal (inkomen, vermogen, participatie); neutraal = geen eenduidige relatie. */
export type IndicatorDirection = 'hoog' | 'laag' | 'neutraal'

export type Unit = 'aantal' | 'pct' | 'euro' | 'per_km2' | 'per_1000' | 'km' | 'personen' | 'index'

export interface Indicator {
  id: string
  label: string
  shortLabel: string
  unit: Unit
  theme: string
  description: string
  direction: IndicatorDirection
  /** jaren waarin deze indicator gemeentebreed beschikbaar is (indicatief;
   *  views bepalen beschikbaarheid dynamisch per scope/niveau) */
  years: number[]
  derived?: string
  /** true = zorg-/welzijns-/gezondheidsuitkomst (Y in de samenhang-analyse) */
  isOutcome?: boolean
  /** bijv. 'gemodelleerd' voor RIVM-kleine-gebiedsschattingen */
  estimateType?: string
  /** domeingroep voor uitkomsten (ervaren_gezondheid, mentaal, …) */
  domain?: string
}

export interface Theme {
  id: string
  title: string
  dynamoService: string
  description: string
  indicatorIds: string[]
  headline: string[]
}

/** values[regionCode][indicatorId][yearIndex] — null = niet beschikbaar/geheim */
export type ValueStore = Record<string, Record<string, (number | null)[]>>

/** officialForecast[regionCode][indicatorId][jaar] = puntwaarde uit een externe
 *  officiële prognose (bijv. gemeentelijke O&S-bevolkingsprognose/BBGA), los van
 *  de intern getrokken trendprognose in lib/forecast.ts. Alleen gevuld waar zo'n
 *  bron bestaat (nu: Oost-stadsdeel/wijken). Geen onzekerheidsband: de bronnen
 *  publiceren geen interval. */
export type OfficialForecastStore = Record<string, Record<string, Record<number, number>>>

export interface GentComponentCfg {
  id: string
  label: string
  mode: 'pct' | 'pp'
  sign: 1 | -1
  why: string
}

export interface GentConfig {
  components: GentComponentCfg[]
  note: string
}

export interface Dataset {
  meta: {
    title: string
    source: string
    generated: string
    yearsCovered: number[]
    gemeente: string
  }
  years: number[]
  regions: Region[]
  themes: Theme[]
  indicators: Indicator[]
  values: ValueStore
  gentrification?: GentConfig
  outcomeIds?: string[]
  correlation?: { rivmMeetjaren: number[]; note: string }
  officialForecast?: OfficialForecastStore
}

export interface GemeenteIndex {
  default: string
  gemeenten: { code: string; naam: string; levels: RegionLevel[] }[]
}

/* ---------- GeoJSON (minimale typing voor de choropleth) ---------- */

export interface GeoFeature {
  type: 'Feature'
  properties: { code: string; name: string }
  geometry: {
    type: 'Polygon' | 'MultiPolygon'
    coordinates: number[][][] | number[][][][]
  }
}

export interface GeoCollection {
  type: 'FeatureCollection'
  features: GeoFeature[]
}
