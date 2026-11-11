//! Plain data types shared across SecureVault crates.
//!
//! This crate contains identifiers, version markers and error types only.
//! It performs no cryptography.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Errors for validating shared types.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum TypeError {
    /// An identifier was empty.
    #[error("identifier must not be empty")]
    EmptyId,
    /// An identifier contained characters outside `[A-Za-z0-9_-]`.
    #[error("identifier contains invalid characters")]
    InvalidId,
    /// A key version of zero is reserved and invalid.
    #[error("key version must be greater than zero")]
    InvalidKeyVersion,
}

fn validate_id(raw: &str) -> Result<(), TypeError> {
    if raw.is_empty() {
        return Err(TypeError::EmptyId);
    }
    if !raw
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err(TypeError::InvalidId);
    }
    Ok(())
}

macro_rules! id_type {
    ($(#[$m:meta])* $name:ident) => {
        $(#[$m])*
        #[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
        #[serde(try_from = "String", into = "String")]
        pub struct $name(String);

        impl $name {
            /// Creates a validated identifier.
            pub fn new(raw: impl Into<String>) -> Result<Self, TypeError> {
                let raw = raw.into();
                validate_id(&raw)?;
                Ok(Self(raw))
            }

            /// Returns the identifier as a string slice.
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl TryFrom<String> for $name {
            type Error = TypeError;
            fn try_from(value: String) -> Result<Self, Self::Error> {
                Self::new(value)
            }
        }

        impl From<$name> for String {
            fn from(value: $name) -> String {
                value.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(&self.0)
            }
        }
    };
}

id_type!(
    /// Identifier of a vault.
    VaultId
);
id_type!(
    /// Identifier of an encrypted item.
    ItemId
);
id_type!(
    /// Identifier of a registered device.
    DeviceId
);

/// Monotonic version of a key, used for rotation. Zero is invalid.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct KeyVersion(u32);

impl KeyVersion {
    /// Creates a key version; rejects zero.
    pub fn new(v: u32) -> Result<Self, TypeError> {
        if v == 0 {
            Err(TypeError::InvalidKeyVersion)
        } else {
            Ok(Self(v))
        }
    }

    /// Returns the numeric version.
    pub fn get(self) -> u32 {
        self.0
    }

    /// Returns the next version, or `None` on overflow.
    pub fn next(self) -> Option<Self> {
        self.0.checked_add(1).map(Self)
    }
}

/// Version of the encrypted data format. Algorithms are not selected yet.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct FormatVersion(pub u16);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn id_rejects_empty_and_invalid() {
        assert_eq!(VaultId::new(""), Err(TypeError::EmptyId));
        assert_eq!(ItemId::new("a b"), Err(TypeError::InvalidId));
        assert!(DeviceId::new("dev_1-A").is_ok());
    }

    #[test]
    fn id_serde_validates() {
        let ok: VaultId = serde_json::from_str("\"v-1\"").unwrap();
        assert_eq!(ok.as_str(), "v-1");
        assert!(serde_json::from_str::<VaultId>("\"bad id\"").is_err());
    }

    #[test]
    fn key_version_rules() {
        assert!(KeyVersion::new(0).is_err());
        let v = KeyVersion::new(1).unwrap();
        assert_eq!(v.next().unwrap().get(), 2);
        assert!(KeyVersion::new(u32::MAX).unwrap().next().is_none());
    }
}
