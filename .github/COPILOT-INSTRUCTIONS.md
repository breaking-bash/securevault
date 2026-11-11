SecureVault – Master Project Specification
1. Project Objective

Build SecureVault, a production-oriented, cross-platform password manager inspired by the functionality of 1Password.

The application must support:

Windows x64 and ARM64
Linux x86_64 and ARM64
macOS Intel and Apple Silicon
Android
iOS
Chrome
Firefox
Microsoft Edge
Brave

The application must use a shared Rust security engine and platform-specific user interfaces and integrations.

Do not copy proprietary source code, branding, assets or proprietary designs from other password managers.

2. Technology Stack
Desktop
Tauri 2
Rust
React
TypeScript
Vite
Browser Extension
WebExtensions API
TypeScript
Manifest V3 where supported
Native Messaging
Mobile
Tauri 2 mobile support where appropriate
Kotlin platform integrations
Swift platform integrations
Android Keystore
Apple Keychain
Backend
Go
REST API
OpenAPI
PostgreSQL
Redis
S3-compatible encrypted object storage
Infrastructure
Docker
GitHub Actions
Terraform
Cloud deployment
Centralized monitoring
3. Architecture Rules

Use a monorepo.

The shared Rust core must contain:

Cryptographic operations
Key management
Vault management
Data validation
Password generation
Local storage
Synchronization logic
Shared data structures

The frontend must never implement its own independent cryptographic protocol.

Use narrow, explicitly authorized Tauri commands.

Never expose unrestricted filesystem, shell or process execution to the frontend.

4. Repository Structure

apps/ desktop/ browser-extension/ mobile/ admin-console/

crates/ shared-types/ crypto-engine/ key-manager/ vault-engine/ storage-engine/ sync-engine/ password-generator/ platform-security/

backend/ cmd/ internal/ auth/ users/ devices/ vaults/ sync/ organizations/ audit/ migrations/

infrastructure/ docker/ terraform/ monitoring/

docs/ architecture/ security/ api/ threat-model/

5. Security Requirements

Security is the highest priority.

Use established cryptographic libraries and independently reviewed algorithms.

Initial cryptographic design candidates:

Argon2id for password-based key derivation.
XChaCha20-Poly1305 for authenticated encryption.
HKDF-SHA-256 for key derivation.
OS cryptographic random number generators.
Zeroize for sensitive memory where practical.

Requirements:

Never store plaintext vault passwords in the cloud.
Never send master passwords to the backend.
Never log plaintext credentials.
Never hardcode encryption keys.
Never reuse AEAD nonces with the same key.
Authenticate ciphertext and associated data.
Use independent keys for vaults and cryptographic purposes.
Implement key versioning and rotation.
Protect local device-unlock material using platform security facilities.
Support device revocation.
Design secure account recovery.
Implement secure encrypted synchronization.
Document all cryptographic decisions.

Do not invent cryptographic algorithms.

Do not implement production account recovery or shared-vault key distribution without a documented, reviewed protocol.

6. Core Features
Password Management
Add login
Edit login
Delete login
Secure notes
Credit cards
Identities
SSH keys
API credentials
Password generator
Search
Tags
Favorites
Vault Management
Create vault
Rename vault
Delete vault
Multiple vaults
Vault permissions
Shared vaults
Security
Secure account unlocking
Auto-lock
MFA
Device management
Key rotation
Recovery
Security dashboard
Weak password detection
Reused password detection
Breach monitoring where supported
Browser
Login form detection
User-approved autofill
Password capture
Native Messaging
Origin verification
Browser-specific packaging
Cloud
Account authentication
Device registration
Encrypted synchronization
Conflict handling
Encrypted attachments
Audit events
Organization management
Enterprise
Teams
Roles
Shared vaults
Access policies
SSO integration
Admin console
Audit logs
7. Database Requirements

Use PostgreSQL.

Initial entities:

users
auth_credentials
devices
organizations
organization_members
vaults
vault_members
encrypted_items
vault_key_envelopes
sync_operations
attachments
sessions
audit_events

Only store encrypted vault payloads and the metadata required for synchronization and authorization.

Use database migrations.

Enforce tenant isolation and server-side authorization.

8. Development Standards
Follow Rust formatting and linting conventions.
Use TypeScript strict mode.
Use Go formatting and linting.
Write unit tests for all core modules.
Write integration tests for APIs.
Write cryptographic known-answer and tamper-detection tests.
Document public APIs.
Commit dependency lockfiles.
Scan dependencies for known vulnerabilities.
Use structured error handling.
Never commit secrets.
Keep modules small and maintainable.
9. Development Phases

Phase 1: Architecture, threat model, protocol specification and repository setup.

Phase 2: Rust security engine and local encrypted vault.

Phase 3: Tauri desktop application.

Phase 4: Cloud backend and encrypted synchronization.

Phase 5: Browser extensions and Native Messaging.

Phase 6: Android and iOS integrations.

Phase 7: Organizations, shared vaults and administration.

Phase 8: Security audit, cross-platform testing and production deployment.

10. GitHub Copilot Agent Instructions

Work incrementally.

Do not generate the entire application in one operation.

Before implementing a module:

Inspect the existing repository.
Read the project specification.
Identify module dependencies.
Explain the implementation plan.
Implement the smallest useful increment.
Add tests.
Run formatting, linting and tests.
Document the result.
Report incomplete functionality and security limitations.

Do not claim a feature is complete when it is only a placeholder.

Do not silently change the architecture.

Do not replace the selected technologies without explaining the reason.

Do not implement insecure shortcuts to make tests pass.

When a security requirement is ambiguous, stop and document the decision needed.

Prioritize correctness, maintainability, testability and security over implementation speed.

11. First Milestone

Start with the repository foundation.

Create:

Rust workspace
Shared types crate
Crypto engine interface
Key manager interface
Vault engine interface
Tauri desktop shell
React and TypeScript frontend
Go backend skeleton
PostgreSQL migration framework
GitHub Actions CI
Architecture documentation
Security threat model

The first milestone must compile and pass its automated tests.

Do not claim production-grade encryption until the cryptographic protocol has been fully specified, implemented and independently reviewed.