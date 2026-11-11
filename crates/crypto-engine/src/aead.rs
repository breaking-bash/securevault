use crate::{Aead, CryptoError, KeyPurpose, Sealed, KEY_LEN};
use chacha20poly1305::aead::{Aead as _, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use shared_types::KeyVersion;
use zeroize::Zeroizing;

const NONCE_LEN: usize = 24;
const TAG_LEN: usize = 16;
const DOMAIN: &[u8] = b"sv/v1/aead";

/// XChaCha20-Poly1305 AEAD bound to one key, key version and purpose.
///
/// A fresh random 24-byte nonce is generated for every `seal`. The key
/// version, format version, purpose and caller associated data are all
/// authenticated, so ciphertext cannot be moved across contexts.
pub struct XChaChaAead {
    key: Zeroizing<[u8; KEY_LEN]>,
    key_version: KeyVersion,
    purpose: KeyPurpose,
}

impl std::fmt::Debug for XChaChaAead {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("XChaChaAead")
            .field("key", &"<redacted>")
            .field("key_version", &self.key_version)
            .field("purpose", &self.purpose)
            .finish()
    }
}

impl XChaChaAead {
    /// Creates an AEAD from a 32-byte key.
    pub fn new(
        key: &[u8],
        key_version: KeyVersion,
        purpose: KeyPurpose,
    ) -> Result<Self, CryptoError> {
        let key: [u8; KEY_LEN] = key
            .try_into()
            .map_err(|_| CryptoError::InvalidInput("key must be 32 bytes"))?;
        Ok(Self {
            key: Zeroizing::new(key),
            key_version,
            purpose,
        })
    }

    fn cipher(&self) -> XChaCha20Poly1305 {
        XChaCha20Poly1305::new(self.key.as_ref().into())
    }

    fn full_aad(&self, format: u16, key_version: KeyVersion, ad: &[u8]) -> Vec<u8> {
        let label = self.purpose.label();
        let mut v = Vec::with_capacity(DOMAIN.len() + label.len() + 14 + ad.len());
        v.extend_from_slice(DOMAIN);
        v.extend_from_slice(&format.to_be_bytes());
        v.extend_from_slice(&key_version.get().to_be_bytes());
        v.extend_from_slice(&(label.len() as u32).to_be_bytes());
        v.extend_from_slice(label);
        v.extend_from_slice(ad);
        v
    }
}

impl Aead for XChaChaAead {
    fn seal(
        &self,
        purpose: KeyPurpose,
        associated_data: &[u8],
        plaintext: &[u8],
    ) -> Result<Sealed, CryptoError> {
        if purpose != self.purpose {
            return Err(CryptoError::InvalidInput("key purpose mismatch"));
        }
        let mut nonce = [0u8; NONCE_LEN];
        getrandom::fill(&mut nonce).map_err(|_| CryptoError::Randomness)?;
        let aad = self.full_aad(Sealed::CURRENT_FORMAT.0, self.key_version, associated_data);
        let ct = self
            .cipher()
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: plaintext,
                    aad: &aad,
                },
            )
            .map_err(|_| CryptoError::InvalidInput("encryption failure"))?;
        let mut bytes = Vec::with_capacity(NONCE_LEN + ct.len());
        bytes.extend_from_slice(&nonce);
        bytes.extend_from_slice(&ct);
        Ok(Sealed {
            format: Sealed::CURRENT_FORMAT,
            key_version: self.key_version,
            bytes,
        })
    }

    fn open(
        &self,
        purpose: KeyPurpose,
        associated_data: &[u8],
        sealed: &Sealed,
    ) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
        if purpose != self.purpose {
            return Err(CryptoError::InvalidInput("key purpose mismatch"));
        }
        if sealed.format != Sealed::CURRENT_FORMAT {
            return Err(CryptoError::InvalidInput("unsupported format version"));
        }
        if sealed.key_version != self.key_version {
            return Err(CryptoError::InvalidInput("key version mismatch"));
        }
        if sealed.bytes.len() < NONCE_LEN + TAG_LEN {
            return Err(CryptoError::InvalidInput("ciphertext too short"));
        }
        let (nonce, ct) = sealed.bytes.split_at(NONCE_LEN);
        let aad = self.full_aad(sealed.format.0, sealed.key_version, associated_data);
        self.cipher()
            .decrypt(XNonce::from_slice(nonce), Payload { msg: ct, aad: &aad })
            .map(Zeroizing::new)
            .map_err(|_| CryptoError::AuthenticationFailed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn aead(key: u8, v: u32, p: KeyPurpose) -> XChaChaAead {
        XChaChaAead::new(&[key; KEY_LEN], KeyVersion::new(v).unwrap(), p).unwrap()
    }

    const P: KeyPurpose = KeyPurpose::ItemEncryption;

    #[test]
    fn roundtrip() {
        let a = aead(1, 1, P);
        let s = a.seal(P, b"ctx", b"hello").unwrap();
        assert_eq!(a.open(P, b"ctx", &s).unwrap().as_slice(), b"hello");
        assert_eq!(s.bytes.len(), NONCE_LEN + 5 + TAG_LEN);
    }

    #[test]
    fn empty_plaintext_roundtrip() {
        let a = aead(1, 1, P);
        let s = a.seal(P, b"", b"").unwrap();
        assert!(a.open(P, b"", &s).unwrap().is_empty());
    }

    #[test]
    fn nonces_are_unique() {
        let a = aead(1, 1, P);
        let n1 = a.seal(P, b"", b"x").unwrap().bytes[..NONCE_LEN].to_vec();
        let n2 = a.seal(P, b"", b"x").unwrap().bytes[..NONCE_LEN].to_vec();
        assert_ne!(n1, n2);
    }

    #[test]
    fn every_flipped_bit_position_fails() {
        let a = aead(1, 1, P);
        let s = a.seal(P, b"ctx", b"secret").unwrap();
        for i in 0..s.bytes.len() {
            let mut t = s.clone();
            t.bytes[i] ^= 1;
            assert_eq!(
                a.open(P, b"ctx", &t),
                Err(CryptoError::AuthenticationFailed),
                "byte {i}"
            );
        }
    }

    #[test]
    fn wrong_associated_data_fails() {
        let a = aead(1, 1, P);
        let s = a.seal(P, b"ctx", b"secret").unwrap();
        assert_eq!(
            a.open(P, b"other", &s),
            Err(CryptoError::AuthenticationFailed)
        );
    }

    #[test]
    fn wrong_key_fails() {
        let s = aead(1, 1, P).seal(P, b"", b"secret").unwrap();
        assert_eq!(
            aead(2, 1, P).open(P, b"", &s),
            Err(CryptoError::AuthenticationFailed)
        );
    }

    #[test]
    fn wrong_purpose_fails() {
        let a = aead(1, 1, P);
        assert!(a.seal(KeyPurpose::KeyWrapping, b"", b"x").is_err());
        let s = a.seal(P, b"", b"x").unwrap();
        assert!(a.open(KeyPurpose::KeyWrapping, b"", &s).is_err());
        // Same key bytes under a different purpose must not open it either.
        let other = aead(1, 1, KeyPurpose::KeyWrapping);
        assert_eq!(
            other.open(KeyPurpose::KeyWrapping, b"", &s),
            Err(CryptoError::AuthenticationFailed)
        );
    }

    #[test]
    fn version_tampering_fails() {
        let a = aead(1, 1, P);
        let mut s = a.seal(P, b"", b"x").unwrap();
        s.key_version = KeyVersion::new(2).unwrap();
        assert!(a.open(P, b"", &s).is_err());
        // Even a matching-version key cannot open it: version is in the AAD.
        assert_eq!(
            aead(1, 2, P).open(P, b"", &s),
            Err(CryptoError::AuthenticationFailed)
        );
        let mut s = a.seal(P, b"", b"x").unwrap();
        s.format = shared_types::FormatVersion(2);
        assert!(a.open(P, b"", &s).is_err());
    }

    #[test]
    fn truncated_input_fails() {
        let a = aead(1, 1, P);
        let mut s = a.seal(P, b"", b"x").unwrap();
        s.bytes.truncate(NONCE_LEN + TAG_LEN - 1);
        assert!(a.open(P, b"", &s).is_err());
    }

    #[test]
    fn rejects_bad_key_length_and_redacts_debug() {
        assert!(XChaChaAead::new(&[0u8; 16], KeyVersion::new(1).unwrap(), P).is_err());
        let d = format!("{:?}", aead(7, 1, P));
        assert!(d.contains("redacted") && !d.contains("7, 7"));
    }
}
