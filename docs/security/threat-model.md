# SecureVault Initial Threat Model (Phase 1, DRAFT)

> No security controls are implemented yet. This document records intended
> mitigations and the work needed. It must be reviewed before Phase 2.

## Assets

Master password / user secret, vault keys, vault item plaintext, session
tokens, device keys, sync metadata, audit logs.

## Trust boundaries

1. UI (webview) ↔ Rust core (Tauri IPC)
2. Client ↔ backend (network)
3. Backend ↔ PostgreSQL / Redis / S3
4. Device ↔ OS (clipboard, memory, disk, other processes)

## Threats and intended mitigations

| # | Threat | Intended mitigation | Status |
|---|--------|--------------------|--------|
| T1 | Server/DB breach exposes vault data | Client-side encryption; server stores ciphertext only | Not implemented |
| T2 | Master password sent to server | Password never leaves client; opaque auth verifier | Not implemented |
| T3 | Malicious/compromised webview script | Strict CSP; no crypto in JS; narrow IPC commands; empty capability set | Partially (CSP + empty capabilities) |
| T4 | Overly broad Tauri permissions | Explicit per-command capabilities; no fs/shell/process | Applied to scaffold |
| T5 | Nonce reuse / weak randomness | Fresh nonce per seal; OS RNG; tested | Interface contract only |
| T6 | Key reuse across purposes | `KeyPurpose` separation; HKDF subkeys | Interface only |
| T7 | Ciphertext tampering / rollback | AEAD with associated data; revision counters | Not implemented |
| T8 | Secrets lingering in memory/logs | zeroize; no secret logging; structured errors | Not implemented |
| T9 | Session theft / replay | Hashed tokens at rest, expiry, revocation | Schema only |
| T10 | Malicious org admin / shared vault abuse | Reviewed key-distribution protocol; audit events | Not designed |
| T11 | Account recovery abuse | Reviewed recovery protocol | Not designed |
| T12 | Supply-chain compromise | Lockfiles committed, dependency scanning in CI | Lockfiles only; scanning TODO |
| T13 | Local malware / keylogger / clipboard sniffing | Out of scope to fully prevent; auto-clear clipboard, lock timeouts | Not implemented |
| T14 | Injection into backend | Parameterized queries, input validation | Not implemented |

## Out of scope (initially)

Compromised OS/kernel, hardware attacks, coercion.

## Required before any release

Algorithm selection review, authentication protocol design, independent
cryptographic review, dependency audit (`cargo audit`, `npm audit`,
`govulncheck`), and known-answer/tamper tests.
