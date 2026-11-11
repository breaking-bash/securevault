# SecureVault

A **native, cross-platform, zero-knowledge password manager** for **Windows, Linux and Android**, built from a single Flutter codebase.

Everything is stored **only on your device** — there is no server, no cloud, no sync, and no account registration with anyone. Your logins, secure notes and folders are encrypted at rest with keys derived from a master password that never leaves your device and is never written to disk.

---

## Table of contents
1. [Feature overview](#feature-overview)
2. [Security model](#security-model)
3. [How & where data is stored](#how--where-data-is-stored)
4. [Architecture](#architecture)
5. [Build & run — Linux](#build--run--linux)
6. [Build & run — Android (APK)](#build--run--android-apk)
7. [Build & run — Windows](#build--run--windows)
8. [Verification status](#verification-status)
9. [Project layout](#project-layout)
10. [Security notes & limitations](#security-notes--limitations)

---

## Feature overview

**Accounts (local, on-device)**
- Multiple local profiles on one device, each with its **own master password** and its **own encrypted vault file**.
- First-run flow creates an account + master password; later launches show the unlock screen.
- Switch between accounts, add new accounts, and **change the master password** (re-encrypts the whole vault).

**Vault items**
- **Logins** with: title, username/email, password, URL, notes, folder, optional TOTP secret, and created/updated timestamps.
- **Secure notes** — free-form encrypted notes.
- **Credit cards** — cardholder, number, expiry, CVV and PIN.
- **SSH keys** — generate Ed25519 key pairs (OpenSSH format) or paste your own.
- **Passkeys** — vault-stored passkey items (website, user, credential ID, private key). These are stored records only; SecureVault is not yet a system passkey provider.
- **1Password-style UI** — "New Item" button with a category grid (Login, Credit Card, Identity, Bank Account, Wi-Fi, Passkey, SSH Key, Server, Database, API Credential, License, Driver License, Passport, Email Account, Secure Note), coloured category icons, and an animated padlock on the unlock screen (closes on launch, shakes on a wrong password, opens on success; also for fingerprint unlock).
- **Rich fields** — every item can have extra fields (text, URL, email, date, one-time password, password, phone), a "Sign in with" provider on logins, tags, and encrypted file attachments (up to 5 MB each).
- **Watchtower** — flags weak, reused, old, HTTP and missing-2FA logins, and checks breaches via Have I Been Pwned (k-anonymity: only a 5-character SHA-1 prefix is sent).
- **Secret Key** — a per-account 128-bit key (SV1-XXXXXX-...) mixed with the master password (Argon2id + HKDF), required on new devices. Existing accounts can enable it in Settings.
- **Link another device** — QR-code pairing over the local network; the vault is sent encrypted (X25519 + AES-256-GCM), and the master password and Secret Key are never transmitted.
- **Folders / categories** to organise items; filter the list by folder.
- **Search** across titles, usernames, URLs and notes.

**Password tools**
- **Configurable password generator** (length 6–64, upper/lower/digits/symbols, exclude ambiguous characters) — available standalone and inline while editing an entry.
- Live **password-strength** indicator.

**Security UX**
- **Copy to clipboard** with **automatic clipboard clearing** after a configurable timeout (default 30s) for sensitive values.
- **Show / hide** password toggles.
- **Auto-lock** with selectable behaviour: **Immediately** (locks the instant the app is backgrounded/loses focus), **Never**, or an idle timeout of **1 / 3 / 5 / 15 minutes**. Re-entry requires the master password (or biometrics, if enabled).
- **Biometric / fingerprint unlock** (opt-in, per account) — unlock with your device fingerprint/face while keeping the zero-knowledge model.
- **Two-factor (TOTP)** — scan an `otpauth://` **QR code** to store a secret, then view a **live RFC 6238 code with a countdown** on the entry.
- Minimalist **Material 3** UI with **light / dark / system** themes.

---

## What's new in this release

### 1. Auto-lock "Immediately"
The auto-lock setting (Settings → Security → *Auto-lock*) now offers **Immediately** in addition to *Never / 1 / 3 / 5 / 15 min*.
- **Immediately** — the vault locks the moment the app is backgrounded, minimised or loses focus (zero idle grace). No idle timer is used.
- The timed options keep their previous behaviour: the idle-timeout timer runs (including while backgrounded) and locks the vault when it elapses.
- The choice is persisted in the app settings file and honoured by `VaultState`.

### 2. Fingerprint / biometric unlock
Opt in per account under **Settings → Security → Biometric unlock** (only shown on devices that support biometrics).

**How it works (zero-knowledge preserved):**
- When you enable it, SecureVault runs a biometric prompt (`local_auth`) and then seals **your master password** into the platform's **biometric-gated, hardware-backed keystore** — on Android this is `EncryptedSharedPreferences` via `flutter_secure_storage`. The master password is therefore still **never written to app storage in plaintext** and never leaves the device.
- On the next launch, the unlock screen offers **"Unlock with biometrics"**. A successful biometric check releases the stored master password from the keystore, which is then used to derive the key exactly as a manual unlock would. The derived key still lives only in RAM.
- **Master-password fallback is always available** — biometrics never replace the password, they just unlock it.
- **Disabling** biometric unlock (toggle off, or it is unavailable) **deletes the stored secret** from the keystore. Changing the master password automatically re-seals the new one if biometrics are enabled.

**Security tradeoff (read this):** enabling biometric unlock trades a small amount of security for convenience. Anyone who can satisfy the device's biometric/credential check (a registered fingerprint/face, or the device PIN/pattern used as the secure fallback) can unlock that account **without** knowing the master password. The secret is protected by the OS keystore and is only as strong as your device lock. If you want the strongest posture, leave biometrics **off** and unlock with the master password only. Biometrics are **off by default**.

### 3. TOTP QR-code scanner + live codes
- When adding/editing a login, the **TOTP secret** field has a **Scan QR** button (Android/iOS). It opens the camera (`mobile_scanner`), reads an `otpauth://totp/...` QR code, parses the base32 secret (and issuer/account/digits/period) and fills in the secret. The secret is stored **encrypted** like every other field.
- On the entry's detail screen, a **live 6-digit code** (RFC 6238) is shown with a **countdown ring** and refreshes automatically every period; tap to copy.
- **Manual entry still works everywhere** — you can type/paste a base32 secret, and on desktop (no camera) the field falls back to manual entry gracefully.
- Android adds the **`CAMERA`** permission (used only for scanning); it is requested at runtime by the scanner and is declared `android:required="false"` so camera-less devices still install.

### 4. Minimalist UI redesign
The whole app was restyled into a clean, Bitwarden-inspired Material 3 look:
- A **3-tab bottom navigation**: **Vault · Generator · Settings**.
- The Vault tab uses a large bold title, a search row, a **"Vault: All"** filter row with an overflow menu (manage folders / switch account / lock), and **grouped sections with uppercase headers and counts** — **TYPES** (Login, Secure note), **FOLDERS**, and **NO FOLDER** — rendered as simple **full-width divider-separated rows** (monochrome outline icon + label, trailing count + chevron) instead of heavy cards.
- Generous whitespace, a single blue accent used sparingly, and a floating **+** button. The same clean aesthetic is applied across unlock, entry detail/edit, generator and settings.
- **No functionality was removed** — logins, secure notes, folders, multi-account, search, the generator, clipboard auto-clear and master-password change all remain.

---

## Security model

SecureVault is **zero-knowledge**: the vault contents can only be read by someone who knows the master password. Even with full access to the device's files, the stored data is unreadable ciphertext.

### Key derivation (KDF)
- Algorithm: **Argon2id** (memory-hard, resistant to GPU/ASIC brute force) via the `cryptography` package.
- Parameters: **19 MiB memory, 3 iterations, 1 lane**, producing a **256-bit** key.
- Each account has a unique, cryptographically-random **16-byte salt**.
- The salt and KDF parameters are stored (they are not secret); the **master password and derived key are never stored**. The key exists only in RAM while the vault is unlocked and is dropped on lock.

### Encryption at rest
- Cipher: **AES-256-GCM** (authenticated encryption with associated data) via the `cryptography` package.
- Every secret-bearing record (login payload, note payload, folder name) is serialised to JSON and encrypted into a self-describing blob of **nonce + ciphertext + authentication tag**, with a fresh random nonce per encryption.
- GCM's authentication tag means **any tampering with the ciphertext is detected** on decrypt (decryption fails rather than returning corrupted data).

### Unlock verification
- On account creation, a fixed known constant is encrypted with the master key to form a **verifier** blob.
- On unlock, the entered password is run through Argon2id and used to decrypt the verifier. If it decrypts to the expected constant, the password is correct — this verifies the password **without** touching (or risking corruption of) the real vault data.
- A wrong password simply fails the verifier (and could never decrypt any record anyway, because GCM authentication would fail).

### What is stored in plaintext vs. encrypted

| Data | Stored as |
|------|-----------|
| Login title, username, password, URL, notes, TOTP | **Encrypted** (AES-256-GCM) |
| Secure note title & body | **Encrypted** |
| Folder name | **Encrypted** |
| Record IDs, folder reference IDs, created/updated timestamps | Plaintext (opaque; reveal no content) |
| Per-account: display name, KDF salt, KDF parameters, unlock verifier | Plaintext metadata (contain no secrets) |
| Master password, derived key | **Never stored** (RAM only, while unlocked) |

> There is no password recovery. If you forget the master password, the data is cryptographically unrecoverable — by design.

---

## How & where data is stored

All data lives in the OS per-app **application-support directory** (resolved via `path_provider`), under a `securevault/` subfolder:

- `accounts.json` — the list of local accounts (non-secret metadata: name, salt, KDF params, verifier).
- `settings.json` — non-secret app preferences (theme, auto-lock minutes, clipboard-clear seconds).
- `vault_<accountId>.db` — one **encrypted SQLite database per account** holding the encrypted `entries`, `notes`, `folders` payloads.

Typical locations:

| Platform | Path |
|----------|------|
| Linux | `~/.local/share/securevault/` (under the app's support dir) |
| Windows | `%APPDATA%\com.securevault\securevault\securevault\` (app support dir) |
| Android | App-private internal storage (`/data/data/com.securevault.securevault/...`) — not accessible to other apps |

The SQLite layer is **cross-platform**: it uses the `sqflite` plugin on Android and the FFI backend (`sqflite_common_ffi` + the bundled native `sqlite3` from `sqlite3_flutter_libs`) on Linux/Windows desktop. The database only ever contains encrypted blobs for secret fields.

---

## Architecture

```
lib/
├── main.dart                     App entry, theme wiring, lifecycle-based auto-lock
├── models/                       Plain data models + secret-JSON (de)serialisation
│   ├── account.dart              LocalAccount (salt, KDF params, verifier — no secrets)
│   ├── vault_entry.dart          Login entry
│   ├── secure_note.dart          Secure note
│   └── folder.dart               Folder / category
├── services/
│   ├── crypto_service.dart       Argon2id KDF + AES-256-GCM + verifier (the core)
│   ├── account_service.dart      Create/list/rename/delete local accounts (accounts.json)
│   ├── database_service.dart     Per-account encrypted SQLite (Android + desktop FFI)
│   ├── settings_service.dart     Non-secret app preferences
│   └── password_generator.dart   CSPRNG configurable generator + strength scoring
├── state/
│   └── vault_state.dart          ChangeNotifier: in-memory key, decrypted data,
│                                 CRUD, auto-lock timer, clipboard auto-clear,
│                                 master-password change (full re-encryption)
└── ui/
    ├── theme.dart                Material 3 light/dark themes
    ├── screens/                  welcome, create account, unlock, home,
    │                             entry edit/detail, note edit, settings
    └── widgets/                  reusable password-generator sheet
```

**Data flow:** unlock → Argon2id derives the key → key held in `VaultState` (RAM) → all encrypted rows read from SQLite and decrypted into memory → UI renders decrypted lists → edits are re-encrypted and written back per record → lock/background clears the key and the in-memory data.

---

## Build & run — Linux

**Verified on this project** (Ubuntu 24.04, Flutter 3.27.1).

Install the toolchain (Debian/Ubuntu):
```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config \
     libgtk-3-dev liblzma-dev libsqlite3-dev libstdc++-12-dev
```

Install Flutter (if not present) and enable Linux desktop:
```bash
# https://docs.flutter.dev/get-started/install/linux
flutter config --enable-linux-desktop
```

Build & run:
```bash
cd securevault
flutter pub get
flutter build linux --release        # or: ./scripts/build_linux.sh
./build/linux/x64/release/bundle/securevault
# convenience: ./scripts/build_linux.sh run   (builds then launches)
```
The runnable app is the whole folder `build/linux/x64/release/bundle/` (ship it together).

---

## Build & run — Android (APK)

**A ready-to-install release APK is included: [`dist/SecureVault-1.0.0.apk`](dist/SecureVault-1.0.0.apk)** (~24 MB, built on this project).

> It is signed with the standard Android **debug** key so it installs directly. For publishing to the Play Store you should create your own upload/release keystore and configure `android/app/build.gradle` signing (see below).

Install on a device:
```bash
adb install dist/SecureVault-1.0.0.apk
# or copy the .apk to the phone and open it (enable "install from unknown sources")
```

Rebuild the APK yourself:
```bash
# Prerequisites: JDK 17, Android SDK (platform-tools, platform android-35, build-tools),
# ANDROID_SDK_ROOT set, licenses accepted (flutter doctor --android-licenses)
cd securevault
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

Optional — split per-ABI (smaller APKs) or an App Bundle:
```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release        # .aab for Play Store
```

Use your own release signing (for store distribution): create a keystore, add a `android/key.properties`, and replace `signingConfigs.debug` in `android/app/build.gradle` with your release config — see the [Flutter signing guide](https://docs.flutter.dev/deployment/android#signing-the-app).

---

## Build & run — Windows

> **A Windows `.exe` cannot be compiled on Linux** — it requires the MSVC toolchain from Visual Studio, which only runs on Windows. The `windows/` runner target is **fully configured** in this project; build it on a Windows machine with the one-command script below.

Prerequisites (install once on Windows):
1. **Flutter SDK** (stable) — https://docs.flutter.dev/get-started/install/windows
2. **Visual Studio 2022** with the **“Desktop development with C++”** workload (provides MSVC, the Windows SDK and CMake).
3. `flutter config --enable-windows-desktop`

Build (from the project root, in PowerShell):
```powershell
./scripts/build_windows.ps1
```
or in cmd.exe:
```bat
scripts\build_windows.bat
```
or manually:
```powershell
flutter pub get
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\securevault.exe` plus its DLLs (including the bundled `sqlite3.dll`). **Distribute the entire `Release` folder** (zip it) — the executable needs the DLLs beside it. The app is self-contained and needs no installer.

---

## Verification status

What was built and checked on this Linux VM:

| Item | Status |
|------|--------|
| `flutter analyze` | ✅ No issues found |
| Unit/integration tests (`flutter test`) | ✅ 8/8 pass |
| → Argon2id derive + AES-GCM round-trip | ✅ |
| → Wrong master password rejected (GCM auth) | ✅ |
| → **Confirmed no plaintext secrets on disk** (ciphertext only) | ✅ |
| → Search filter, password-change re-encryption, generator options | ✅ |
| Linux release build (`flutter build linux --release`) | ✅ Built |
| Linux app launches & runs (headless xvfb) | ✅ Starts without crashing |
| Android release APK (`flutter build apk --release`) | ✅ Built, 24.4 MB, signed, `apksigner verify` OK → `dist/SecureVault-1.0.0.apk` |
| Windows runner configured + build scripts | ✅ Configured (compile must run on Windows — not possible on Linux) |

> The Linux app was verified to **build and launch** in a headless environment; interactive flows (create account, add entry, search, generator) are exercised end-to-end by the automated tests against the real crypto + SQLite storage layers. The Windows `.exe` has **not** been compiled here because this is a Linux machine — build it on Windows with the provided script.

---

## Project layout

```
securevault/
├── lib/                  Dart source (see Architecture)
├── test/                 Crypto + storage-pipeline tests
├── android/              Android native project (APK target)
├── linux/                Linux native runner (GTK)
├── windows/             Windows native runner (configured; build on Windows)
├── scripts/
│   ├── build_linux.sh    One-command Linux build (+ optional run)
│   ├── build_windows.ps1 One-command Windows build (PowerShell)
│   └── build_windows.bat One-command Windows build (cmd)
├── dist/
│   └── SecureVault-1.0.0.apk   Prebuilt installable Android APK
├── pubspec.yaml
└── README.md
```

---

## Security notes & limitations

- **No recovery / no backdoor.** Forgetting the master password means the vault is unrecoverable. Keep a safe backup of the password.
- **Backups are your responsibility.** Since data is device-local only, copy the `securevault/` app-support folder (all encrypted) if you want a backup. Restoring requires the same master password.
- **At-rest, not anti-malware.** Encryption protects data on disk and when the app is locked. While the vault is **unlocked**, decrypted data is in RAM (as with any password manager). Auto-lock and background-lock reduce this exposure window.
- **Clipboard.** Copied passwords are auto-cleared after the configured timeout, but other apps/clipboard managers may still observe clipboard contents during that window.
- **Argon2id cost** is tuned for responsiveness across phones and desktops. You can raise `kdfMemoryKiB` / `kdfIterations` in `lib/services/crypto_service.dart` for a higher security margin (existing vaults keep their stored parameters; new/changed passwords use the new cost).
- **Debug-signed APK** is for direct install/testing. Use your own release keystore before any store distribution.
```
