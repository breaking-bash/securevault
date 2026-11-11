//! Crypto engine interface.
//!
//! **This crate defines contracts only. It contains NO cryptographic
//! implementation and must not be treated as providing any security.**
//! Algorithm selection (candidates: Argon2id, XChaCha20-Poly1305,
//! HKDF-SHA-256) is a Phase 2 decision requiring documented review.

use shared_types::{FormatVersion, KeyVersion};

/// Errors returned by crypto-engine implementations.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CryptoError {
    /// No implementation is available.
    #[error("cryptographic implementation not available")]
    NotImplemented,
    /// Authentication of ciphertext failed (tampering or wrong key).
    #[error("authentication failed")]
    AuthenticationFailed,
    /// Input was malformed or unsupported.
    #[error("invalid input: {0}")]
    InvalidInput(&'static str),
    /// The entropy source failed.
    #[error("randomness source failure")]
    Randomness,
}

/// Purpose of a derived key. Keys must never be shared across purposes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum KeyPurpose {
    /// Encrypting vault item payloads.
    ItemEncryption,
    /// Wrapping other keys.
    KeyWrapping,
    /// Authenticating sync metadata.
    SyncAuthentication,
}

/// Opaque envelope of an encrypted payload. The layout is not yet specified.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sealed {
    /// Data format version.
    pub format: FormatVersion,
    /// Version of the key used.
    pub key_version: KeyVersion,
    /// Opaque bytes; contents are defined by a future reviewed protocol.
    pub bytes: Vec<u8>,
}

/// Authenticated encryption interface.
///
/// Implementations MUST generate a fresh nonce per call and MUST bind
/// `associated_data` to the ciphertext.
pub trait Aead {
    /// Encrypts and authenticates `plaintext`.
    fn seal(
        &self,
        purpose: KeyPurpose,
        associated_data: &[u8],
        plaintext: &[u8],
    ) -> Result<Sealed, CryptoError>;

    /// Verifies and decrypts `sealed`.
    fn open(
        &self,
        purpose: KeyPurpose,
        associated_data: &[u8],
        sealed: &Sealed,
    ) -> Result<Vec<u8>, CryptoError>;
}

/// Password-based key derivation interface.
pub trait PasswordKdf {
    /// Derives key material from a secret and salt.
    fn derive(&self, secret: &[u8], salt: &[u8]) -> Result<Vec<u8>, CryptoError>;
}

/// Purpose-bound subkey derivation interface.
pub trait SubkeyDeriver {
    /// Derives an independent key for `purpose` from `root`.
    fn derive_subkey(&self, root: &[u8], purpose: KeyPurpose) -> Result<Vec<u8>, CryptoError>;
}

/// Secure random source interface.
pub trait SecureRandom {
    /// Fills `out` with random bytes from the OS RNG.
    fn fill(&self, out: &mut [u8]) -> Result<(), CryptoError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Always-failing stub proving the traits are object-safe. Not crypto.
    struct Unavailable;

    impl SecureRandom for Unavailable {
        fn fill(&self, _out: &mut [u8]) -> Result<(), CryptoError> {
            Err(CryptoError::NotImplemented)
        }
    }

    impl Aead for Unavailable {
        fn seal(&self, _: KeyPurpose, _: &[u8], _: &[u8]) -> Result<Sealed, CryptoError> {
            Err(CryptoError::NotImplemented)
        }
        fn open(&self, _: KeyPurpose, _: &[u8], _: &Sealed) -> Result<Vec<u8>, CryptoError> {
            Err(CryptoError::NotImplemented)
        }
    }

    #[test]
    fn traits_are_object_safe_and_fail_closed() {
        let a: Box<dyn Aead> = Box::new(Unavailable);
        assert_eq!(
            a.seal(KeyPurpose::ItemEncryption, b"", b"x"),
            Err(CryptoError::NotImplemented)
        );
        let r: Box<dyn SecureRandom> = Box::new(Unavailable);
        assert_eq!(r.fill(&mut [0u8; 4]), Err(CryptoError::NotImplemented));
    }
}
