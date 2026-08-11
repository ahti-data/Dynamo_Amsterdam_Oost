import type { Dataset } from '../types'
import type { AppState } from '../App'

export function Inzichten({ ds: _ds, state: _state }: { ds: Dataset; state: AppState }) {
  return (
    <>
      <h1 className="view-title">Inzichten</h1>
      <p className="view-sub view-sub-wide">
        Nog in ontwikkeling — welke doelgroepdossiers en uitkomsten hier komen, wordt later
        bepaald.
      </p>
      <div className="card">
        <div className="empty-state">
          <p>TBD later</p>
        </div>
      </div>
    </>
  )
}
