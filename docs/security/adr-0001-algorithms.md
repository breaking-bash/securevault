# ADR-0001: Cryptographic algorithm selection (PROPOSED)

> **Status: approved by the project owner (2026-11-11). Independent cryptographic review is still pending.**
> Implementation starts with `crypto-engine`. Do not claim production readiness.

## Decisions requested

| Area | Proposal | Reference |
|------|----------|-----------|
| Password KDF | Argon2id, 19 MiB / t=2 / p=1 minimum (target 64 MiB / t=3), 16-byte random salt, params stored with the data | RFC 9106 |
| AEAD | XChaCha20-Poly1305, 32-byte keys, 24-byte random nonce per seal | draft-irtf-cfrg-xchacha |
| Subkey derivation | HKDF-SHA-256, one `info` string per `KeyPurpose` (`sv/v1/item`, `sv/v1/wrap`, `sv/v1/sync`) | RFC 5869 |
| Randomness | OS RNG via `getrandom`; failure is a hard error, never a fallback | |
| Memory hygiene | `zeroize` on all key types; no `Debug`/`Display` on secrets | |
| Secret Key | 128-bit random, combined with the password-derived key via HKDF (two-secret derivation, as in the current Flutter app) | |
| Server auth | OPAQUE (augmented PAKE) so the master password never reaches the server | RFC 9807 |

## Key hierarchy

1. `password_key = Argon2id(master_password, salt)`
2. `account_unlock_key = HKDF(password_key || secret_key, info="sv/v1/auk")`
3. Each vault has a random 256-bit `vault_key`, wrapped by `account_unlock_key`
   (AEAD, AAD = vault id + key version). Rotation creates a new `KeyVersion`.
4. `item_key = HKDF(vault_key, info="sv/v1/item")`; items sealed with AAD =
   vault id + item id + key version + format version, binding ciphertext to its context.

## Envelope (`Sealed.bytes`)

`format_version (u16) | key_version (u32) | nonce (24) | ciphertext+tag`

Unknown format versions are rejected. Format/key versions are also in the AAD.

## Why

- Argon2id: memory-hard, current standard; params versioned for upgrades.
- XChaCha20 with 192-bit nonces makes random nonces safe at vault scale
  (no counter state to lose in a sync/restore scenario), and avoids AES
  hardware dependence.
- HKDF gives independent purpose keys, per the "no key reuse" rule.
- Using vetted RustCrypto crates: `argon2`, `chacha20poly1305`, `hkdf`, `sha2`,
  `zeroize`, `getrandom`. No custom primitives.

## Tests required before merge

- Known-answer vectors from the RFCs/crate test suites (Argon2id, HKDF-SHA-256, XChaCha20-Poly1305).
- Tamper tests: flipped bit in ciphertext, nonce, AAD, key/format version all fail.
- Wrong key and wrong purpose fail; nonces differ across seals; zeroization compiles in.
- `cargo audit` and `cargo deny` in CI.

## Open questions for the reviewer

1. Are the Argon2id parameters acceptable for low-end Android devices?
2. OPAQUE implementation choice (`opaque-ke` crate) and its audit status.
3. Is migrating existing Flutter AES-256-GCM vaults acceptable via a one-time importer (see `mobile-migration.md`)?
4. Account recovery and shared-vault key distribution remain **out of scope** until separately designed.

## Environment note

Native builds are blocked by Application Control on the dev machine; crypto
tests will run in CI and WSL.
