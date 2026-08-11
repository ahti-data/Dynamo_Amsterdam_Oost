/** Dynamo-doelgroepen: CBS-indicator gekoppeld aan de dienst die erop stuurt.
 *  Gedeeld tussen de Vooruitblik-view en de view-params-balk in App.tsx. */
export interface TargetGroup {
  id: string
  label: string
  short: string
  service: string
  color: string
}

export const GROUPS: TargetGroup[] = [
  { id: 'a_65_oo', label: 'Ouderen (65-plus)', short: '65-plus', service: 'Ouderenwerk, seniorenactiviteiten, welzijn op recept', color: 'var(--series-3)' },
  { id: 'a_00_14', label: 'Kinderen (0–14 jaar)', short: '0–14 jr', service: 'Kinderwerk en jeugdwerk', color: 'var(--series-1)' },
  { id: 'a_15_24', label: 'Jongeren (15–24 jaar)', short: '15–24 jr', service: 'Jongerenwerk en talentontwikkeling', color: 'var(--series-2)' },
  { id: 'a_1p_hh', label: 'Alleenwonenden', short: 'alleenwonend', service: 'Buurtwerk en eenzaamheidsbestrijding', color: 'var(--series-5)' },
  { id: 'a_45_64', label: 'Aankomende senioren (45–64 jr)', short: '45–64 jr', service: 'Mantelzorg en voorbereiding op vergrijzing', color: 'var(--series-8)' },
  { id: 'a_hh', label: 'Huishoudens', short: 'huishoudens', service: 'Buurtwerk, Huizen van de Wijk, wonen', color: 'var(--series-6)' },
  { id: 'a_inw', label: 'Totaal inwoners', short: 'inwoners', service: 'Draagvlak en schaal van alle voorzieningen', color: 'var(--series-4)' },
]
