import { useMemo, useRef, useState } from 'react'
import type { GeoCollection, Unit } from '../types'
import { fmtValue } from '../lib/format'
import { TooltipBox, TipRow, useTooltip } from './Tooltip'

const SEQ = ['var(--seq-100)', 'var(--seq-200)', 'var(--seq-300)', 'var(--seq-400)', 'var(--seq-500)', 'var(--seq-600)', 'var(--seq-700)']
const DIV = [
  'var(--div-neg-3)', 'var(--div-neg-2)', 'var(--div-neg-1)', 'var(--div-mid)',
  'var(--div-pos-1)', 'var(--div-pos-2)', 'var(--div-pos-3)',
]
// unieke pattern-id per instantie (meerdere kaarten op één pagina)
let patternSeq = 0

interface Props {
  geo: GeoCollection
  values: Record<string, number | null>
  unit: Unit
  /** 'seq' = absolute waarden; 'div' = afwijking t.o.v. referentie (0 = midden) */
  mode: 'seq' | 'div'
  selected?: string | null
  onSelect?: (code: string) => void
  labelFor: (code: string) => string
  height?: number
  /** subtekst in de tooltip, bijv. referentiewaarde */
  tipExtra?: (code: string) => { label: string; value: string } | null
  /** koppeling met de staafgrafiek: licht dit vlak op (hover elders) */
  hovered?: string | null
  /** koppeling met de staafgrafiek: meld welk vlak onder de muis ligt */
  onHover?: (code: string | null) => void
  /** vaste schaalgrenzen (bijv. over alle jaren) zodat kleuren vergelijkbaar blijven */
  domain?: { min: number; max: number }
  /** true = lage waarde is het sterkste signaal: keer de kleurschaal om */
  invert?: boolean
  /** toegankelijke naam van de kaart */
  ariaLabel?: string
  /** uitleg bij een vlak zonder data: welke gegevens ontbreken om dit te tonen */
  noDataReason?: (code: string) => string
  /** labels voor de uiteinden van de divergerende legenda (M9); default = t.o.v.
   *  een referentiewaarde. Vooruitblik toont geen referentie maar krimp/groei. */
  divLabels?: { low: string; high: string }
  /** true = de meegegeven (vaste) domein-bovengrens is zelf al op een percentiel
   *  gekapt (M6); toon dan het "+"-teken ook al is er een expliciet domein */
  capped?: boolean
}

/** Vlakkenkaart (choropleth) van GeoJSON in WGS84, eigen SVG-projectie. */
export function Choropleth({
  geo,
  values,
  unit,
  mode,
  selected,
  onSelect,
  labelFor,
  height = 420,
  tipExtra,
  hovered,
  onHover,
  domain,
  invert = false,
  ariaLabel,
  noDataReason,
  divLabels,
  capped = false,
}: Props) {
  const ref = useRef<HTMLDivElement>(null)
  const [w, setW] = useState(720)
  const { tip, show, hide } = useTooltip()
  const [hover, setHover] = useState<string | null>(null)
  const hatchId = useMemo(() => `nodata-hatch-${patternSeq++}`, [])

  const measure = (el: HTMLDivElement | null) => {
    ;(ref as React.MutableRefObject<HTMLDivElement | null>).current = el
    if (el && el.clientWidth !== w && el.clientWidth > 0) setW(el.clientWidth)
  }

  /* projectie: equirectangular met cos(lat)-correctie, gefit op viewBox */
  const proj = useMemo(() => {
    let minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity
    const eachCoord = (cb: (lon: number, lat: number) => void) => {
      for (const f of geo.features) {
        const polys =
          f.geometry.type === 'Polygon'
            ? [f.geometry.coordinates as number[][][]]
            : (f.geometry.coordinates as number[][][][])
        for (const poly of polys)
          for (const ring of poly) for (const [lon, lat] of ring) cb(lon, lat)
      }
    }
    eachCoord((lon, lat) => {
      if (lon < minLon) minLon = lon
      if (lon > maxLon) maxLon = lon
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    })
    const cosLat = Math.cos(((minLat + maxLat) / 2) * (Math.PI / 180))
    const pad = 10
    const spanX = (maxLon - minLon) * cosLat
    const spanY = maxLat - minLat
    const scale = Math.min((w - pad * 2) / spanX, (height - pad * 2) / spanY)
    const offX = (w - spanX * scale) / 2
    const offY = (height - spanY * scale) / 2
    return {
      x: (lon: number) => offX + (lon - minLon) * cosLat * scale,
      y: (lat: number) => offY + (maxLat - lat) * scale,
    }
  }, [geo, w, height])

  const paths = useMemo(() => {
    return geo.features.map((f) => {
      const polys =
        f.geometry.type === 'Polygon'
          ? [f.geometry.coordinates as number[][][]]
          : (f.geometry.coordinates as number[][][][])
      let d = ''
      for (const poly of polys) {
        for (const ring of poly) {
          ring.forEach(([lon, lat], i) => {
            d += `${i === 0 ? 'M' : 'L'}${proj.x(lon).toFixed(1)},${proj.y(lat).toFixed(1)}`
          })
          d += 'Z'
        }
      }
      return { code: f.properties.code, d }
    })
  }, [geo, proj])

  /* kleurschaal */
  const vals = Object.values(values).filter((v): v is number => v != null)
  const hasData = vals.length > 0
  const rawMin = domain ? domain.min : hasData ? Math.min(...vals) : 0
  const rawMax = domain ? domain.max : hasData ? Math.max(...vals) : 0
  const NODATA = `url(#${hatchId})`
  // divergerend plafond: expliciet domein, anders het 85e percentiel van |v| zodat
  // uitschieters het middengebied niet platdrukken (meer kleurvariatie)
  const divCap = useMemo(() => {
    if (mode !== 'div') return 1
    if (domain) return Math.max(Math.abs(domain.min), Math.abs(domain.max), 0.0001)
    const abs = vals.map((v) => Math.abs(v)).sort((a, b) => a - b)
    if (!abs.length) return 1
    const p = abs[Math.min(abs.length - 1, Math.floor(abs.length * 0.85))]
    return Math.max(p, 0.0001)
  }, [mode, domain, vals])
  const divCapped = mode === 'div' && !domain && vals.some((v) => Math.abs(v) > divCap)

  // sequentiële modus: zonder uitschieterbescherming drukt één extreme wijk alle
  // andere in de lichtste klasse (M6) — kap het bovenste bereik op het 90e
  // percentiel wanneer er geen expliciet (vast) domein is meegegeven
  const seqMax = useMemo(() => {
    if (mode !== 'seq' || domain || vals.length < 5) return rawMax
    const sorted = [...vals].sort((a, b) => a - b)
    const p = sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.9))]
    return Math.max(p, rawMin + 0.0001)
  }, [mode, domain, vals, rawMax, rawMin])
  const seqCapped = mode === 'seq' && (seqMax < rawMax || capped)
  const vMin = rawMin
  const vMax = mode === 'seq' ? seqMax : rawMax

  const fill = (v: number | null): string => {
    if (v == null) return NODATA
    if (mode === 'div') {
      const t = Math.max(-1, Math.min(1, v / divCap))
      // symmetrisch afbeelden op de 7 stappen, midden = index 3
      const i = Math.round(t * 3) + 3
      return DIV[Math.max(0, Math.min(DIV.length - 1, i))]
    }
    if (vMax === vMin) return SEQ[3]
    let t = Math.max(0, Math.min(1, (v - vMin) / (vMax - vMin)))
    if (invert) t = 1 - t // laag = sterkste signaal -> donker
    return SEQ[Math.min(SEQ.length - 1, Math.floor(t * SEQ.length))]
  }
  const ramp = mode === 'div' ? DIV : SEQ
  const low = divLabels?.low ?? 'onder referentie'
  const high = divLabels?.high ?? 'boven referentie'

  return (
    <div className="viz-wrap" ref={measure}>
      <svg
        width="100%"
        height={height}
        viewBox={`0 0 ${w} ${height}`}
        role="group"
        aria-label={ariaLabel ?? 'Vlakkenkaart'}
      >
        <defs>
          <pattern id={hatchId} patternUnits="userSpaceOnUse" width="6" height="6" patternTransform="rotate(45)">
            <rect width="6" height="6" fill="var(--surface-2)" />
            <line x1="0" y1="0" x2="0" y2="6" stroke="var(--text-muted)" strokeWidth="1.1" opacity="0.55" />
          </pattern>
        </defs>
        {paths.map(({ code, d }) => {
          const v = values[code] ?? null
          const isSel = selected === code
          const isHover = hover === code || hovered === code
          const showTip = (x: number, y: number) => {
            const extra = tipExtra?.(code)
            const reason = v == null ? noDataReason?.(code) : undefined
            show(
              x,
              y,
              <>
                <div className="viz-tip-title">{labelFor(code)}</div>
                <TipRow label="" value={v == null ? 'geen data' : fmtValue(v, unit)} />
                {reason ? <div className="viz-tip-reason">{reason}</div> : null}
                {extra ? <TipRow label={extra.label} value={extra.value} muted /> : null}
              </>,
            )
          }
          return (
            <path
              key={code}
              d={d}
              fill={fill(v)}
              stroke={isSel ? 'var(--text-primary)' : 'var(--surface-1)'}
              strokeWidth={isSel ? 2 : 1.25}
              opacity={isHover ? 0.82 : 1}
              className={onSelect ? 'viz-geo clickable' : 'viz-geo'}
              tabIndex={onSelect ? 0 : undefined}
              role={onSelect ? 'button' : undefined}
              aria-label={`${labelFor(code)}: ${v == null ? 'geen data' : fmtValue(v, unit)}`}
              onKeyDown={
                onSelect
                  ? (e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault()
                        onSelect(code)
                      }
                    }
                  : undefined
              }
              onFocus={(e) => {
                setHover(code)
                onHover?.(code)
                const host = ref.current?.getBoundingClientRect()
                const box = e.currentTarget.getBoundingClientRect()
                if (host) showTip(box.left - host.left + box.width / 2, box.top - host.top + box.height / 2)
              }}
              onBlur={() => {
                setHover(null)
                onHover?.(null)
                hide()
              }}
              onPointerMove={(e) => {
                setHover(code)
                onHover?.(code)
                const host = ref.current?.getBoundingClientRect()
                if (!host) return
                showTip(e.clientX - host.left, e.clientY - host.top)
              }}
              onPointerLeave={() => {
                setHover(null)
                onHover?.(null)
                hide()
              }}
              onClick={onSelect ? () => onSelect(code) : undefined}
            />
          )
        })}
        {/* opgelicht vlak (hover vanuit de staafgrafiek) duidelijk omlijnen */}
        {hovered &&
          paths
            .filter((p) => p.code === hovered)
            .map((p) => (
              <path
                key="hovered"
                d={p.d}
                fill="none"
                stroke="var(--text-primary)"
                strokeWidth={2.5}
                pointerEvents="none"
              />
            ))}
        {/* selectie bovenop tekenen zodat de rand niet wegvalt */}
        {selected &&
          paths
            .filter((p) => p.code === selected)
            .map((p) => (
              <path
                key="sel"
                d={p.d}
                fill="none"
                stroke="var(--text-primary)"
                strokeWidth={2}
                pointerEvents="none"
              />
            ))}
      </svg>
      <div className="viz-map-legend" aria-hidden>
        {hasData ? (
          <>
            <span className="viz-axis-text">
              {mode === 'div'
                ? `${low} (${fmtValue(-divCap, unit)}${divCapped ? '+' : ''})`
                : fmtValue(invert ? vMax : vMin, unit)}
            </span>
            <span className="viz-ramp">
              {ramp.map((c, i) => (
                <span key={i} style={{ background: c }} />
              ))}
            </span>
            <span className="viz-axis-text">
              {mode === 'div'
                ? `${high} (${fmtValue(divCap, unit)}${divCapped ? '+' : ''})`
                : `${fmtValue(invert ? vMin : vMax, unit)}${seqCapped ? '+' : ''}`}
            </span>
            {invert && <span className="viz-axis-text">· donker = sterkste signaal (lage waarde)</span>}
            {(divCapped || seqCapped) && (
              <span className="viz-axis-text">· uiterste waarden afgetopt op de schaal ("+")</span>
            )}
            {Object.values(values).some((v) => v == null) && (
              <span className="legend-item">
                <span className="viz-nodata-swatch" /> geen data
              </span>
            )}
          </>
        ) : (
          <span className="viz-axis-text">geen data voor deze selectie</span>
        )}
      </div>
      <TooltipBox tip={tip} width={w} />
    </div>
  )
}
