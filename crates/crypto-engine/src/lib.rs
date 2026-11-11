//! SecureVault crypto engine, implementing ADR-0001
//! (`docs/security/adr-0001-algorithms.md`).
//!
//! Primitives come from the RustCrypto crates (Argon2id, XChaCha20-Poly1305,
//! HKDF-SHA-256) and the OS RNG. **This code has not had an independent
//! cryptographic review and must not be treated as production-ready.**

mod aead;
mod kdf;
mod rng;

pub use aead::XChaChaAead;
pub use kdf::{hkdf_sha256_subkey, Argon2idKdf, Argon2idParams, HkdfSubkeys};
pub use rng::OsRandom;

use shared_types::{FormatVersion, KeyVersion};
use zeroize::Zeroizing;

/// Length in bytes of all symmetric keys.
pub const KEY_LEN: usize = 32;

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

impl KeyPurpose {
    /// HKDF `info` label for this purpose.
    pub fn label(self) -> &'static [u8] {
        match self {
            KeyPurpose::ItemEncryption => b"sv/v1/item",
            KeyPurpose::KeyWrapping => b"sv/v1/wrap",
            KeyPurpose::SyncAuthentication => b"sv/v1/sync",
        }
    }
}

/// Envelope of an encrypted payload.
///
/// `bytes` is `nonce (24) || ciphertext || tag (16)`. The wire form
/// (`to_wire`/`from_wire`) prepends `format_version (u16 BE) | key_version (u32 BE)`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sealed {
    /// Data format version.
    pub format: FormatVersion,
    /// Version of the key used.
    pub key_version: KeyVersion,
    /// Nonce followed by ciphertext and tag.
    pub bytes: Vec<u8>,
}

impl Sealed {
    /// The only format version this crate can read or write.
    pub const CURRENT_FORMAT: FormatVersion = FormatVersion(1);

    /// Serializes to the wire format.
    pub fn to_wire(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(6 + self.bytes.len());
        out.extend_from_slice(&self.format.0.to_be_bytes());
        out.extend_from_slice(&self.key_version.get().to_be_bytes());
        out.extend_from_slice(&self.bytes);
        out
    }

    /// Parses the wire format; rejects unknown format versions.
    pub fn from_wire(wire: &[u8]) -> Result<Self, CryptoError> {
        if wire.len() < 6 {
            return Err(CryptoError::InvalidInput("envelope too short"));
        }
        let format = FormatVersion(u16::from_be_bytes([wire[0], wire[1]]));
        if format != Self::CURRENT_FORMAT {
            return Err(CryptoError::InvalidInput("unsupported format version"));
        }
        let kv = u32::from_be_bytes([wire[2], wire[3], wire[4], wire[5]]);
        let key_version =
            KeyVersion::new(kv).map_err(|_| CryptoError::InvalidInput("invalid key version"))?;
        Ok(Self {
            format,
            key_version,
            bytes: wire[6..].to_vec(),
        })
    }
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
    ) -> Result<Zeroizing<Vec<u8>>, CryptoError>;
}

/// Password-based key derivation interface.
pub trait PasswordKdf {
    /// Derives key material from a secret and salt.
    fn derive(&self, secret: &[u8], salt: &[u8]) -> Result<Zeroizing<Vec<u8>>, CryptoError>;
}

/// Purpose-bound subkey derivation interface.
pub trait SubkeyDeriver {
    /// Derives an independent key for `purpose` from `root`.
    fn derive_subkey(
        &self,
        root: &[u8],
        purpose: KeyPurpose,
    ) -> Result<Zeroizing<Vec<u8>>, CryptoError>;
}

/// Secure random source interface.
pub trait SecureRandom {
    /// Fills `out` with random bytes from the OS RNG.
    fn fill(&self, out: &mut [u8]) -> Result<(), CryptoError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn traits_are_object_safe() {
        let _: Box<dyn Aead> = Box::new(
            XChaChaAead::new(
                &[7u8; KEY_LEN],
                KeyVersion::new(1).unwrap(),
                KeyPurpose::ItemEncryption,
            )
            .unwrap(),
        );
        let _: Box<dyn SecureRandom> = Box::new(OsRandom);
        let _: Box<dyn PasswordKdf> =
            Box::new(Argon2idKdf::new(Argon2idParams::minimum()).unwrap());
        let _: Box<dyn SubkeyDeriver> = Box::new(HkdfSubkeys);
    }

    #[test]
    fn wire_roundtrip_and_rejections() {
        let s = Sealed {
            format: Sealed::CURRENT_FORMAT,
            key_version: KeyVersion::new(3).unwrap(),
            bytes: vec![1, 2, 3],
        };
        assert_eq!(Sealed::from_wire(&s.to_wire()).unwrap(), s);
        assert!(Sealed::from_wire(&[0, 1]).is_err());
        let mut bad = s.to_wire();
        bad[1] = 9;
        assert!(Sealed::from_wire(&bad).is_err());
        let mut zero_kv = s.to_wire();
        zero_kv[2..6].copy_from_slice(&0u32.to_be_bytes());
        assert!(Sealed::from_wire(&zero_kv).is_err());
    }
}
