import { Component, type ReactNode } from 'react'

interface State {
  error: Error | null
}

/** Vangt onverwachte renderfouten op zodat de app nooit als leeg scherm eindigt. */
export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  render() {
    if (this.state.error) {
      return (
        <div className="loading" role="alert">
          <div style={{ textAlign: 'center' }}>
            <p>Er ging iets mis in de weergave ({this.state.error.message}).</p>
            <button
              className="control"
              style={{ backgroundImage: 'none' }}
              onClick={() => this.setState({ error: null })}
            >
              Opnieuw proberen
            </button>
          </div>
        </div>
      )
    }
    return this.props.children
  }
}
