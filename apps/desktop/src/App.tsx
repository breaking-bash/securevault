import { useEffect, useState } from 'react'
import { getAppInfo, type AppInfo } from './api'

export default function App() {
  const [info, setInfo] = useState<AppInfo | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    getAppInfo()
      .then(setInfo)
      .catch(() => setError('Desktop core unavailable'))
  }, [])

  return (
    <main>
      <h1>SecureVault</h1>
      <p role="status">
        Phase 1 scaffold. No encryption is implemented; do not store real
        secrets.
      </p>
      {info && (
        <p>
          Core: {info.name} v{info.version}
        </p>
      )}
      {error && <p role="alert">{error}</p>}
    </main>
  )
}
