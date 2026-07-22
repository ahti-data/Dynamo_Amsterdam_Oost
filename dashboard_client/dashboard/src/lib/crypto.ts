/* ============================================================================
 * Client-side ontsleuteling van de databundels.
 *
 * De gedeployde build kan versleuteld zijn (zie deploy/encrypt_data.py): elk
 * databestand staat dan als `<naam>.enc` op de server en een publiek
 * `data/enc-meta.json` beschrijft de KDF-parameters. Zonder het juiste wachtwoord
 * is er niets bruikbaars op te halen — óók niet via directe download.
 *
 * Automatische modusdetectie: bestaat `data/enc-meta.json` → encryptie-modus
 * (toon ontgrendelscherm, ontsleutel client-side). Bestaat het niet (dev/preview
 * op platte JSON) → gewone modus, geen wachtwoord.
 *
 * Ontsleuteling gebeurt met de Web Crypto API — vereist een **secure context**
 * (HTTPS of localhost). Over kaal HTTP is `crypto.subtle` niet beschikbaar.
 * ========================================================================== */

interface EncMeta {
  v: number
  salt: string // base64
  iter: number
  check: string // base64(iv(12) || ciphertext+tag) van "dynamo-monitor-ok"
}

const CHECK_PLAINTEXT = 'dynamo-monitor-ok'

let mode: 'plain' | 'encrypted' | null = null
let meta: EncMeta | null = null
let key: CryptoKey | null = null

// expliciet ArrayBuffer-backed: Web Crypto (BufferSource) accepteert geen
// Uint8Array<ArrayBufferLike> in de nieuwere TS-lib
function b64ToBytes(b64: string): Uint8Array<ArrayBuffer> {
  const bin = atob(b64)
  const out = new Uint8Array(new ArrayBuffer(bin.length))
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

/** Bepaalt eenmalig of de build versleuteld is (aanwezigheid van enc-meta.json). */
export async function detectEncryption(): Promise<'plain' | 'encrypted'> {
  if (mode) return mode
  try {
    const r = await fetch('./data/enc-meta.json', { cache: 'no-store' })
    if (r.ok) {
      meta = (await r.json()) as EncMeta
      mode = 'encrypted'
      return mode
    }
  } catch {
    /* geen meta → platte modus */
  }
  mode = 'plain'
  return mode
}

export function isEncrypted(): boolean {
  return mode === 'encrypted'
}

export function isUnlocked(): boolean {
  return mode === 'plain' || key != null
}

/** True als de browser client-side kan ontsleutelen (secure context vereist). */
export function cryptoAvailable(): boolean {
  return typeof crypto !== 'undefined' && !!crypto.subtle
}

async function deriveKey(password: string, m: EncMeta): Promise<CryptoKey> {
  const material = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveKey'],
  )
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt: b64ToBytes(m.salt), iterations: m.iter, hash: 'SHA-256' },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['decrypt'],
  )
}

async function decryptBytes(k: CryptoKey, blob: Uint8Array<ArrayBuffer>): Promise<ArrayBuffer> {
  const iv = blob.slice(0, 12)
  const ct = blob.slice(12)
  return crypto.subtle.decrypt({ name: 'AES-GCM', iv }, k, ct)
}

/**
 * Probeer te ontgrendelen met `password`. Geeft true bij succes (sleutel wordt
 * bewaard voor de sessie), false bij een fout wachtwoord.
 */
export async function unlock(password: string): Promise<boolean> {
  if (!meta) throw new Error('geen encryptie-metadata geladen')
  const k = await deriveKey(password, meta)
  try {
    const plain = await decryptBytes(k, b64ToBytes(meta.check))
    if (new TextDecoder().decode(plain) !== CHECK_PLAINTEXT) return false
    key = k
    return true
  } catch {
    return false // GCM-authenticatie faalt → fout wachtwoord
  }
}

/**
 * Laadt en parseert een JSON/GeoJSON-databestand, transparant ontsleuteld in
 * encryptie-modus. In platte modus een gewone fetch.
 */
export async function loadData<T>(url: string, signal?: AbortSignal): Promise<T> {
  if (mode === 'encrypted') {
    if (!key) throw new Error('nog niet ontgrendeld')
    const r = await fetch(`${url}.enc`, { signal })
    if (!r.ok) throw new Error(`${url}.enc: ${r.status}`)
    const buf = await decryptBytes(key, new Uint8Array(await r.arrayBuffer()))
    return JSON.parse(new TextDecoder().decode(buf)) as T
  }
  const r = await fetch(url, { signal })
  if (!r.ok) throw new Error(`${url}: ${r.status}`)
  return r.json() as Promise<T>
}
