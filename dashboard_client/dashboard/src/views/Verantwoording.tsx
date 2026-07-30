import { useEffect, useRef } from 'react'
import type { Dataset } from '../types'
import type { AppState } from '../App'
import { BronLink } from '../components/BronLink'
import { VERANTWOORDING_SECTIONS } from '../lib/verantwoording'

export function Verantwoording({ ds, state }: { ds: Dataset; state: AppState }) {
  const target = state.verantwoordingAnchor
  const scrolledFor = useRef<string | null>(null)

  useEffect(() => {
    if (!target) return
    if (scrolledFor.current === target) return
    scrolledFor.current = target
    const el = document.getElementById(`verant-${target}`)
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    const t = setTimeout(() => state.clearVerantwoordingAnchor(), 2400)
    return () => clearTimeout(t)
  }, [target, state])

  return (
    <div className="prose">
      <h1 className="view-title">Verantwoording & aannames</h1>
      <p className="view-sub">
        Alle keuzes die het analyseteam heeft gemaakt bij het bouwen van deze monitor. Volledige
        technische details staan in <code>docs/AANNAMES.md</code> in de projectmap.
      </p>

      <div className="note">
        <strong>Kern in één zin:</strong> deze monitor toont CBS-cijfers (
        <BronLink state={state} id="cbs-kwb">Kerncijfers Wijken en Buurten 2016–2025</BronLink>)
        aangevuld met gemodelleerde{' '}
        <BronLink state={state} id="rivm-gezondheid">RIVM-gezondheidsuitkomsten</BronLink>, voor
        meerdere gemeenten en alle Amsterdamse gebiedsniveaus, thematisch geordend naar de
        dienstverlening van Dynamo — als signalerings- en verkenningsinstrument, geen
        locatieadviesmodel. Alle bronnen met hun vindplaats staan op het tabblad{' '}
        <BronLink state={state}>Bronnen</BronLink>.
      </div>

      {VERANTWOORDING_SECTIONS.map((sec) => (
        <section
          key={sec.id}
          id={`verant-${sec.id}`}
          className={target === sec.id ? 'is-target' : undefined}
        >
          <h2>{sec.title}</h2>
          {sec.render(state, ds)}
        </section>
      ))}
    </div>
  )
}
