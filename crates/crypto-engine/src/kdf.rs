use crate::{CryptoError, KeyPurpose, PasswordKdf, SubkeyDeriver, KEY_LEN};
use argon2::{Algorithm, Argon2, Params, Version};
use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::Zeroizing;

/// Minimum accepted salt length in bytes.
pub const MIN_SALT_LEN: usize = 16;

/// Argon2id cost parameters. Stored alongside derived data so they can be upgraded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Argon2idParams {
    /// Memory cost in KiB.
    pub memory_kib: u32,
    /// Number of passes.
    pub iterations: u32,
    /// Degree of parallelism.
    pub parallelism: u32,
}

impl Argon2idParams {
    /// Floor accepted by this crate (ADR-0001: 19 MiB, t=2, p=1).
    pub const fn minimum() -> Self {
        Self {
            memory_kib: 19 * 1024,
            iterations: 2,
            parallelism: 1,
        }
    }

    /// Recommended target (ADR-0001: 64 MiB, t=3, p=1).
    pub const fn recommended() -> Self {
        Self {
            memory_kib: 64 * 1024,
            iterations: 3,
            parallelism: 1,
        }
    }
}

/// Argon2id password KDF producing a 32-byte key.
#[derive(Debug, Clone)]
pub struct Argon2idKdf {
    params: Params,
}

impl Argon2idKdf {
    /// Creates a KDF; rejects parameters below the ADR minimum.
    pub fn new(p: Argon2idParams) -> Result<Self, CryptoError> {
        let min = Argon2idParams::minimum();
        if p.memory_kib < min.memory_kib || p.iterations < min.iterations || p.parallelism < 1 {
            return Err(CryptoError::InvalidInput(
                "argon2id parameters below minimum",
            ));
        }
        let params = Params::new(p.memory_kib, p.iterations, p.parallelism, Some(KEY_LEN))
            .map_err(|_| CryptoError::InvalidInput("invalid argon2id parameters"))?;
        Ok(Self { params })
    }
}

impl PasswordKdf for Argon2idKdf {
    fn derive(&self, secret: &[u8], salt: &[u8]) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
        if salt.len() < MIN_SALT_LEN {
            return Err(CryptoError::InvalidInput("salt too short"));
        }
        let mut out = Zeroizing::new(vec![0u8; KEY_LEN]);
        Argon2::new(Algorithm::Argon2id, Version::V0x13, self.params.clone())
            .hash_password_into(secret, salt, &mut out)
            .map_err(|_| CryptoError::InvalidInput("argon2id failure"))?;
        Ok(out)
    }
}

/// HKDF-SHA-256 expand-and-extract of `len` bytes (RFC 5869).
pub fn hkdf_sha256_subkey(
    ikm: &[u8],
    salt: Option<&[u8]>,
    info: &[u8],
    len: usize,
) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
    let mut out = Zeroizing::new(vec![0u8; len]);
    Hkdf::<Sha256>::new(salt, ikm)
        .expand(info, &mut out)
        .map_err(|_| CryptoError::InvalidInput("invalid hkdf output length"))?;
    Ok(out)
}

/// Purpose-separated subkeys via HKDF-SHA-256.
#[derive(Debug, Clone, Copy, Default)]
pub struct HkdfSubkeys;

impl SubkeyDeriver for HkdfSubkeys {
    fn derive_subkey(
        &self,
        root: &[u8],
        purpose: KeyPurpose,
    ) -> Result<Zeroizing<Vec<u8>>, CryptoError> {
        if root.len() < KEY_LEN {
            return Err(CryptoError::InvalidInput("root key too short"));
        }
        hkdf_sha256_subkey(root, None, purpose.label(), KEY_LEN)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    #[test]
    fn hkdf_rfc5869_test_case_1() {
        let ikm = [0x0bu8; 22];
        let salt: Vec<u8> = (0x00..=0x0c).collect();
        let info: Vec<u8> = (0xf0..=0xf9).collect();
        let okm = hkdf_sha256_subkey(&ikm, Some(&salt), &info, 42).unwrap();
        assert_eq!(
            hex(&okm),
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
        );
    }

    #[test]
    fn argon2id_rfc9106_vector() {
        use argon2::ParamsBuilder;
        let params = ParamsBuilder::new()
            .m_cost(32)
            .t_cost(3)
            .p_cost(4)
            .data(argon2::AssociatedData::new(&[4u8; 12]).unwrap())
            .output_len(32)
            .build()
            .unwrap();
        let a = Argon2::new_with_secret(&[3u8; 8], Algorithm::Argon2id, Version::V0x13, params)
            .unwrap();
        let mut out = [0u8; 32];
        a.hash_password_into(&[1u8; 32], &[2u8; 16], &mut out)
            .unwrap();
        assert_eq!(
            hex(&out),
            "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
        );
    }

    #[test]
    fn kdf_is_deterministic_and_salt_sensitive() {
        let k = Argon2idKdf::new(Argon2idParams::minimum()).unwrap();
        let a = k.derive(b"pw", &[1u8; 16]).unwrap();
        assert_eq!(a.len(), KEY_LEN);
        assert_eq!(a, k.derive(b"pw", &[1u8; 16]).unwrap());
        assert_ne!(a, k.derive(b"pw", &[2u8; 16]).unwrap());
        assert_ne!(a, k.derive(b"pw2", &[1u8; 16]).unwrap());
    }

    #[test]
    fn kdf_rejects_weak_inputs() {
        let weak = Argon2idParams {
            memory_kib: 1024,
            ..Argon2idParams::minimum()
        };
        assert!(Argon2idKdf::new(weak).is_err());
        let k = Argon2idKdf::new(Argon2idParams::minimum()).unwrap();
        assert!(k.derive(b"pw", &[1u8; 8]).is_err());
    }

    #[test]
    fn subkeys_are_purpose_separated() {
        let root = [9u8; 32];
        let d = HkdfSubkeys;
        let a = d.derive_subkey(&root, KeyPurpose::ItemEncryption).unwrap();
        let b = d.derive_subkey(&root, KeyPurpose::KeyWrapping).unwrap();
        let c = d
            .derive_subkey(&root, KeyPurpose::SyncAuthentication)
            .unwrap();
        assert_ne!(a, b);
        assert_ne!(b, c);
        assert_ne!(a, c);
        assert!(d.derive_subkey(&[1u8; 8], KeyPurpose::KeyWrapping).is_err());
    }
}
