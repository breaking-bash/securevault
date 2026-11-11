//! Random password generator.
//!
//! All randomness comes from a [`SecureRandom`]. Character selection uses
//! rejection sampling so there is no modulo bias, and the result is shuffled
//! with Fisher-Yates so guaranteed characters are not positionally predictable.

use crypto_engine::{CryptoError, OsRandom, SecureRandom};
use zeroize::Zeroizing;

const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
const UPPER: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS: &str = "0123456789";
const SYMBOLS: &str = "!@#$%^&*()-_=+[]{};:,.<>?/";
const AMBIGUOUS: &str = "Il1O0o";

/// Minimum allowed password length.
pub const MIN_LENGTH: usize = 8;
/// Maximum allowed password length.
pub const MAX_LENGTH: usize = 128;

/// Errors from password generation.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum GeneratorError {
    /// The requested length is outside [`MIN_LENGTH`]..=[`MAX_LENGTH`].
    #[error("length must be between {MIN_LENGTH} and {MAX_LENGTH}")]
    InvalidLength,
    /// No character class is enabled.
    #[error("at least one character class must be enabled")]
    NoCharacterClass,
    /// More classes are required than the length allows.
    #[error("length is too short for the enabled classes")]
    LengthTooShort,
    /// The random source failed.
    #[error(transparent)]
    Random(#[from] CryptoError),
}

/// Password generation policy.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Policy {
    /// Total length.
    pub length: usize,
    /// Include `a-z`.
    pub lowercase: bool,
    /// Include `A-Z`.
    pub uppercase: bool,
    /// Include `0-9`.
    pub digits: bool,
    /// Include punctuation symbols.
    pub symbols: bool,
    /// Exclude visually ambiguous characters (`Il1O0o`).
    pub exclude_ambiguous: bool,
}

impl Default for Policy {
    fn default() -> Self {
        Self {
            length: 20,
            lowercase: true,
            uppercase: true,
            digits: true,
            symbols: true,
            exclude_ambiguous: false,
        }
    }
}

impl Policy {
    fn classes(&self) -> Vec<Vec<char>> {
        [
            (self.lowercase, LOWER),
            (self.uppercase, UPPER),
            (self.digits, DIGITS),
            (self.symbols, SYMBOLS),
        ]
        .into_iter()
        .filter(|(on, _)| *on)
        .map(|(_, set)| {
            set.chars()
                .filter(|c| !(self.exclude_ambiguous && AMBIGUOUS.contains(*c)))
                .collect()
        })
        .collect()
    }
}

/// Uniform random integer in `0..bound` using rejection sampling.
fn uniform(rng: &dyn SecureRandom, bound: usize) -> Result<usize, CryptoError> {
    debug_assert!(bound > 0 && bound <= u32::MAX as usize);
    let bound = bound as u64;
    let zone = (u64::from(u32::MAX) + 1) / bound * bound;
    loop {
        let mut buf = [0u8; 4];
        rng.fill(&mut buf)?;
        let v = u64::from(u32::from_le_bytes(buf));
        if v < zone {
            return Ok((v % bound) as usize);
        }
    }
}

/// Generates a password with an explicit random source.
pub fn generate_with(
    rng: &dyn SecureRandom,
    policy: &Policy,
) -> Result<Zeroizing<String>, GeneratorError> {
    if !(MIN_LENGTH..=MAX_LENGTH).contains(&policy.length) {
        return Err(GeneratorError::InvalidLength);
    }
    let classes = policy.classes();
    if classes.is_empty() {
        return Err(GeneratorError::NoCharacterClass);
    }
    if policy.length < classes.len() {
        return Err(GeneratorError::LengthTooShort);
    }
    let pool: Vec<char> = classes.iter().flatten().copied().collect();

    let mut chars: Vec<char> = Vec::with_capacity(policy.length);
    for class in &classes {
        chars.push(class[uniform(rng, class.len())?]);
    }
    while chars.len() < policy.length {
        chars.push(pool[uniform(rng, pool.len())?]);
    }
    for i in (1..chars.len()).rev() {
        chars.swap(i, uniform(rng, i + 1)?);
    }
    let out: String = chars.iter().collect();
    chars.iter_mut().for_each(|c| *c = '\0');
    Ok(Zeroizing::new(out))
}

/// Generates a password using the operating system RNG.
pub fn generate(policy: &Policy) -> Result<Zeroizing<String>, GeneratorError> {
    generate_with(&OsRandom, policy)
}

/// Generates a numeric PIN of `length` digits (4..=12).
pub fn generate_pin(length: usize) -> Result<Zeroizing<String>, GeneratorError> {
    if !(4..=12).contains(&length) {
        return Err(GeneratorError::InvalidLength);
    }
    let mut out = String::with_capacity(length);
    for _ in 0..length {
        out.push(char::from(b'0' + uniform(&OsRandom, 10)? as u8));
    }
    Ok(Zeroizing::new(out))
}

/// Rough strength estimate in bits of entropy for a policy (upper bound
/// assuming uniform selection; ignores the small effect of guaranteed classes).
pub fn estimated_entropy_bits(policy: &Policy) -> f64 {
    let size: usize = policy.classes().iter().map(Vec::len).sum();
    if size == 0 {
        return 0.0;
    }
    policy.length as f64 * (size as f64).log2()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    /// Deterministic generator for edge-case tests only.
    struct Seq(Cell<u32>, Vec<u32>);
    impl SecureRandom for Seq {
        fn fill(&self, out: &mut [u8]) -> Result<(), CryptoError> {
            let i = self.0.get() as usize;
            self.0.set(self.0.get() + 1);
            out.copy_from_slice(&self.1[i % self.1.len()].to_le_bytes());
            Ok(())
        }
    }

    struct Failing;
    impl SecureRandom for Failing {
        fn fill(&self, _: &mut [u8]) -> Result<(), CryptoError> {
            Err(CryptoError::Randomness)
        }
    }

    #[test]
    fn default_policy_meets_requirements() {
        for _ in 0..200 {
            let p = generate(&Policy::default()).unwrap();
            assert_eq!(p.chars().count(), 20);
            assert!(p.chars().any(|c| c.is_ascii_lowercase()));
            assert!(p.chars().any(|c| c.is_ascii_uppercase()));
            assert!(p.chars().any(|c| c.is_ascii_digit()));
            assert!(p.chars().any(|c| SYMBOLS.contains(c)));
        }
    }

    #[test]
    fn respects_disabled_classes_and_ambiguous_filter() {
        let pol = Policy {
            length: 64,
            symbols: false,
            exclude_ambiguous: true,
            ..Policy::default()
        };
        for _ in 0..50 {
            let p = generate(&pol).unwrap();
            assert!(p.chars().all(|c| c.is_ascii_alphanumeric()));
            assert!(!p.chars().any(|c| AMBIGUOUS.contains(c)));
        }
    }

    #[test]
    fn rejects_bad_policies() {
        let d = Policy::default();
        assert_eq!(
            generate(&Policy { length: 7, ..d }),
            Err(GeneratorError::InvalidLength)
        );
        assert_eq!(
            generate(&Policy { length: 129, ..d }),
            Err(GeneratorError::InvalidLength)
        );
        let none = Policy {
            lowercase: false,
            uppercase: false,
            digits: false,
            symbols: false,
            ..d
        };
        assert_eq!(generate(&none), Err(GeneratorError::NoCharacterClass));
    }

    #[test]
    fn rng_failure_is_propagated() {
        assert_eq!(
            generate_with(&Failing, &Policy::default()),
            Err(GeneratorError::Random(CryptoError::Randomness))
        );
    }

    #[test]
    fn rejection_sampling_discards_biased_zone() {
        // bound 10: zone = 4294967290; values >= zone must be skipped.
        let rng = Seq(Cell::new(0), vec![u32::MAX, 4_294_967_290, 7]);
        assert_eq!(uniform(&rng, 10).unwrap(), 7);
    }

    #[test]
    fn output_is_roughly_uniform() {
        let mut counts = [0usize; 10];
        for _ in 0..20_000 {
            counts[uniform(&OsRandom, 10).unwrap()] += 1;
        }
        // Expected 2000 each; a 25% band is far outside random noise (~45 sd).
        assert!(counts.iter().all(|&c| (1500..2500).contains(&c)));
    }

    #[test]
    fn passwords_are_unique_and_pin_works() {
        let a = generate(&Policy::default()).unwrap();
        let b = generate(&Policy::default()).unwrap();
        assert_ne!(*a, *b);
        let pin = generate_pin(6).unwrap();
        assert_eq!(pin.len(), 6);
        assert!(pin.chars().all(|c| c.is_ascii_digit()));
        assert!(generate_pin(3).is_err());
    }

    #[test]
    fn entropy_estimate_scales_with_length() {
        let p = Policy::default();
        let longer = Policy { length: 40, ..p };
        assert!(estimated_entropy_bits(&longer) > estimated_entropy_bits(&p) * 1.9);
    }
}
