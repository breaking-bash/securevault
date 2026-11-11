use crate::{CryptoError, SecureRandom};

/// Random source backed by the operating system RNG. Failure is a hard error;
/// there is no fallback generator.
#[derive(Debug, Clone, Copy, Default)]
pub struct OsRandom;

impl SecureRandom for OsRandom {
    fn fill(&self, out: &mut [u8]) -> Result<(), CryptoError> {
        getrandom::fill(out).map_err(|_| CryptoError::Randomness)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fills_distinct_buffers() {
        let r = OsRandom;
        let (mut a, mut b) = ([0u8; 32], [0u8; 32]);
        r.fill(&mut a).unwrap();
        r.fill(&mut b).unwrap();
        assert_ne!(a, [0u8; 32]);
        assert_ne!(a, b);
    }
}
