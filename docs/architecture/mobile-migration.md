# Mobile migration plan: Flutter + Rust core

> **Status: plan only.** Nothing here is implemented. No cryptography exists in
> the Rust core yet.

## Decisions

1. **UI toolkit:** keep Flutter; call the Rust core through `flutter_rust_bridge`.
2. **Repository:** a separate repo, `securevault-mobile`. The current Flutter
   app stays in this repo until parity is reached.
3. **Core sharing:** the Rust crates are published as a versioned, tagged
   workspace. The mobile repo pins a tag (git dependency or private registry).
   FFI bindings live in a new `crates/mobile-ffi` crate in this repo, so the
   core stays single-source.

## Phases

| Phase | Goal |
|-------|------|
| M0 | Core Phase 2: select algorithms, implement `crypto-engine`, `key-manager`, `vault-engine`, with known-answer and tamper tests. Blocks everything below. |
| M1 | Create `securevault-mobile`, move the Flutter code with history, set up CI and release workflow, add `flutter_rust_bridge` and `mobile-ffi`. |
| M2 | Move vault encryption, KDF and Secret Key into Rust. Write a one-time importer from the current SQLite/AES-256-GCM format, tested with fixture vaults. Keep the old vault until the new one is verified. |
| M3 | Autofill, passkeys and biometric unlock call into Rust via the bridge, so Kotlin never holds keys. |
| M4 | Sync with the Go backend; device registration and QR device linking on a reviewed protocol. |
| M5 | Ship a migration release, then archive the Flutter code in this repo. |

## Risks

- **Data loss:** the importer must never delete the old vault before the new one is verified.
- **Unverified features:** passkeys, inline autofill and the save flow were never tested on a real device; verify before porting.
- **Local builds:** Application Control blocks native builds on the dev machine; use CI or WSL.
- **Open protocol decisions:** auth scheme, ciphertext envelope, recovery and shared-vault key distribution (see `README.md` in this folder).
