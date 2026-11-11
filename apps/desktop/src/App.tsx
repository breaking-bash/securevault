import { useCallback, useEffect, useRef, useState } from 'react'
import * as api from './api'
import type { LoginItem, VaultStatus } from './api'

const AUTO_LOCK_MS = 5 * 60 * 1000
const EMPTY: LoginItem = { title: '', username: '', password: '', url: '' }

function errorText(e: unknown): string {
  return typeof e === 'string' ? e : 'Something went wrong'
}

function SetupView({ onDone }: { onDone: () => void }) {
  const [pw, setPw] = useState('')
  const [secretKey, setSecretKey] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (secretKey) {
    return (
      <section>
        <h2>Save your Secret Key</h2>
        <p>
          You need this key plus your password to unlock on any device. It is
          shown only once and cannot be recovered.
        </p>
        <code aria-label="secret key">{secretKey}</code>
        <label>
          <input
            type="checkbox"
            checked={saved}
            onChange={(e) => setSaved(e.target.checked)}
          />{' '}
          I have stored my Secret Key safely
        </label>
        <button disabled={!saved} onClick={onDone}>
          Continue
        </button>
      </section>
    )
  }
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        api
          .createAccount(pw)
          .then(setSecretKey)
          .catch((err) => setError(errorText(err)))
      }}
    >
      <h2>Create your vault</h2>
      <label>
        Master password
        <input
          type="password"
          value={pw}
          minLength={8}
          required
          onChange={(e) => setPw(e.target.value)}
        />
      </label>
      <button type="submit">Create</button>
      {error && <p role="alert">{error}</p>}
    </form>
  )
}

function UnlockView({ onDone }: { onDone: () => void }) {
  const [pw, setPw] = useState('')
  const [sk, setSk] = useState('')
  const [error, setError] = useState<string | null>(null)
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        api
          .unlock(pw, sk)
          .then(() => {
            setPw('')
            setSk('')
            onDone()
          })
          .catch((err) => setError(errorText(err)))
      }}
    >
      <h2>Unlock</h2>
      <label>
        Master password
        <input
          type="password"
          value={pw}
          required
          onChange={(e) => setPw(e.target.value)}
        />
      </label>
      <label>
        Secret Key
        <input
          type="password"
          value={sk}
          required
          autoComplete="off"
          onChange={(e) => setSk(e.target.value)}
        />
      </label>
      <button type="submit">Unlock</button>
      {error && <p role="alert">{error}</p>}
    </form>
  )
}

function VaultView({ onLock }: { onLock: () => void }) {
  const [items, setItems] = useState<{ id: string; item: LoginItem }[]>([])
  const [draft, setDraft] = useState<LoginItem>(EMPTY)
  const [revealed, setRevealed] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const [version, setVersion] = useState(0)

  useEffect(() => {
    let live = true
    api
      .listItems()
      .then((ids) =>
        Promise.all(ids.map(async (id) => ({ id, item: await api.getItem(id) }))),
      )
      .then((loaded) => live && setItems(loaded))
      .catch((e) => live && setError(errorText(e)))
    return () => {
      live = false
    }
  }, [version])

  const run = (p: Promise<unknown>) =>
    p.then(() => setVersion((v) => v + 1)).catch((e) => setError(errorText(e)))
  return (
    <section>
      <button onClick={onLock}>Lock</button>
      <h2>Logins</h2>
      {error && <p role="alert">{error}</p>}
      <ul>
        {items.map(({ id, item }) => (
          <li key={id}>
            <strong>{item.title}</strong> {item.username}{' '}
            <span>{revealed === id ? item.password : '••••••••'}</span>{' '}
            <button
              onClick={() => setRevealed(revealed === id ? null : id)}
            >
              {revealed === id ? 'Hide' : 'Reveal'}
            </button>{' '}
            <button onClick={() => run(api.deleteItem(id))}>Delete</button>
          </li>
        ))}
      </ul>
      <form
        onSubmit={(e) => {
          e.preventDefault()
          run(api.saveItem(draft)).then(() => setDraft(EMPTY))
        }}
      >
        <h3>Add login</h3>
        {(['title', 'username', 'url'] as const).map((f) => (
          <label key={f}>
            {f}
            <input
              value={draft[f]}
              required={f === 'title'}
              onChange={(e) => setDraft({ ...draft, [f]: e.target.value })}
            />
          </label>
        ))}
        <label>
          password
          <input
            type="password"
            value={draft.password}
            required
            onChange={(e) => setDraft({ ...draft, password: e.target.value })}
          />
        </label>
        <button
          type="button"
          onClick={() =>
            api
              .generatePassword(20, true)
              .then((password) => setDraft({ ...draft, password }))
              .catch((e) => setError(errorText(e)))
          }
        >
          Generate
        </button>
        <button type="submit">Save</button>
      </form>
    </section>
  )
}

export default function App() {
  const [status, setStatus] = useState<VaultStatus | null>(null)
  const [error, setError] = useState<string | null>(null)
  const timer = useRef<number | undefined>(undefined)

  const refresh = useCallback(
    () =>
      api
        .vaultStatus()
        .then(setStatus)
        .catch(() => setError('Desktop core unavailable')),
    [],
  )

  useEffect(() => {
    void refresh()
  }, [refresh])

  const lock = useCallback(() => api.lock().finally(() => void refresh()), [refresh])

  useEffect(() => {
    if (status !== 'unlocked') return
    const reset = () => {
      window.clearTimeout(timer.current)
      timer.current = window.setTimeout(() => void lock(), AUTO_LOCK_MS)
    }
    const events = ['keydown', 'pointerdown']
    events.forEach((ev) => window.addEventListener(ev, reset))
    reset()
    return () => {
      events.forEach((ev) => window.removeEventListener(ev, reset))
      window.clearTimeout(timer.current)
    }
  }, [status, lock])

  return (
    <main>
      <h1>SecureVault</h1>
      <p role="status">
        Pre-release. The cryptography has not been independently reviewed; do
        not store real secrets yet.
      </p>
      {error && <p role="alert">{error}</p>}
      {status === 'no_account' && <SetupView onDone={() => void refresh()} />}
      {status === 'locked' && <UnlockView onDone={() => void refresh()} />}
      {status === 'unlocked' && <VaultView onLock={() => void lock()} />}
    </main>
  )
}
