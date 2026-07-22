import { useState } from 'react'
import { unlock, cryptoAvailable } from '../lib/crypto'

/** Ontgrendelscherm voor de versleutelde build: zonder juist wachtwoord wordt er
 *  geen (ontsleutelde) data geladen. Verschijnt alleen in encryptie-modus. */
export function UnlockGate({ onUnlocked }: { onUnlocked: () => void }) {
  const [pw, setPw] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const secure = cryptoAvailable()

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!pw || busy) return
    setBusy(true)
    setError(null)
    try {
      const ok = await unlock(pw)
      if (ok) onUnlocked()
      else setError('Onjuist wachtwoord.')
    } catch {
      setError('Ontsleutelen mislukte.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="loading">
      <form
        onSubmit={submit}
        style={{ textAlign: 'center', maxWidth: 340, display: 'grid', gap: 12 }}
        aria-label="Toegang"
      >
        <h1 style={{ fontSize: '1.2rem', margin: 0 }}>Dynamo Monitor</h1>
        {secure ? (
          <>
            <p style={{ margin: 0, color: 'var(--text-secondary)' }}>
              Deze monitor is beveiligd. Voer het wachtwoord in om verder te gaan.
            </p>
            <input
              type="password"
              className="control"
              value={pw}
              autoFocus
              autoComplete="current-password"
              aria-label="Wachtwoord"
              placeholder="Wachtwoord"
              onChange={(e) => setPw(e.target.value)}
              style={{ backgroundImage: 'none', textAlign: 'center' }}
            />
            <button
              type="submit"
              className="control"
              disabled={busy || !pw}
              style={{ backgroundImage: 'none' }}
            >
              {busy ? 'Bezig…' : 'Ontgrendelen'}
            </button>
            {error && (
              <p role="alert" style={{ margin: 0, color: 'var(--negative, #b00)' }}>
                {error}
              </p>
            )}
          </>
        ) : (
          <p role="alert" style={{ margin: 0, color: 'var(--negative, #b00)' }}>
            Ontsleuteling vereist een beveiligde verbinding (HTTPS). Open deze tool via
            <code> https://</code> — over kaal <code>http://</code> kan de browser de data
            niet ontsleutelen.
          </p>
        )}
      </form>
    </div>
  )
}
