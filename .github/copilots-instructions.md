GitHub Copilot Repository Instructions

You are developing SecureVault, a cross-platform password manager.

Always read COPILOT-INSTRUCTIONS.md before making architectural or implementation decisions.

Engineering principles
Rust is the shared security and business logic foundation.
Tauri 2 is the desktop framework.
React and TypeScript are used for desktop interfaces.
WebExtensions is used for browser integrations.
Go is used for backend services.
PostgreSQL is the primary metadata database.
Vault contents must be encrypted on the client before cloud upload.
Security rules
Never store plaintext vault credentials in backend databases.
Never expose master passwords to cloud APIs.
Never invent cryptographic algorithms.
Never hardcode secrets.
Never weaken authentication to simplify development.
Never expose unrestricted frontend-to-native commands.
Validate all untrusted inputs.
Test encryption and tamper detection.
Follow least privilege.
Development workflow
Inspect before modifying.
Make small, reviewable changes.
Add tests with every feature.
Run formatters, linters and tests.
Update documentation.
Preserve existing functionality.
Report assumptions and limitations.
Never mark unfinished functionality as production-ready.
Code quality

Prefer modular, reusable and strongly typed code.

Keep security-sensitive operations inside the Rust core.

Use explicit error handling.

Do not silently swallow errors.

Avoid unnecessary dependencies.

Never commit secrets, credentials or private keys.

Completion reporting

After every implementation task, report:

Files created
Files modified
Features implemented
Tests executed
Tests passed or failed
Security considerations
Remaining work