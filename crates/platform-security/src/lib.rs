//! Platform security abstractions.
//!
//! Defines the biometric/OS-credential gate and an auto-lock policy.
//! Real platform bindings (Android BiometricPrompt + Keystore, Windows Hello,
//! macOS LocalAuthentication) live in per-platform shells; this crate provides
//! the contract and a fail-closed default. A biometric success only *permits*
//! an unlock attempt; it never substitutes for the vault key material.

use std::time::{Duration, Instant};

/// Errors from platform security operations.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PlatformError {
    /// No secure hardware or biometric is available.
    #[error("biometric authentication unavailable")]
    Unavailable,
    /// The user cancelled or failed authentication.
    #[error("authentication denied")]
    Denied,
}

/// Gate requiring a local user-presence check (biometric / device credential).
pub trait BiometricGate {
    /// Whether the gate can currently be used.
    fn is_available(&self) -> bool;
    /// Prompts the user; `Ok(())` only on a confirmed success.
    fn authenticate(&self, reason: &str) -> Result<(), PlatformError>;
}

/// Default gate: never available and never authenticates.
#[derive(Debug, Default, Clone, Copy)]
pub struct FailClosedGate;

impl BiometricGate for FailClosedGate {
    fn is_available(&self) -> bool {
        false
    }
    fn authenticate(&self, _reason: &str) -> Result<(), PlatformError> {
        Err(PlatformError::Unavailable)
    }
}

/// Inactivity timer deciding when the vault must lock. Time is passed in so
/// behaviour is deterministic and testable.
#[derive(Debug, Clone, Copy)]
pub struct AutoLock {
    timeout: Duration,
    last_activity: Instant,
}

impl AutoLock {
    /// Shortest permitted timeout.
    pub const MIN_TIMEOUT: Duration = Duration::from_secs(5);

    /// Creates a timer. Timeouts below [`Self::MIN_TIMEOUT`] are raised to it.
    pub fn new(timeout: Duration, now: Instant) -> Self {
        Self {
            timeout: timeout.max(Self::MIN_TIMEOUT),
            last_activity: now,
        }
    }

    /// Records user activity.
    pub fn touch(&mut self, now: Instant) {
        if now > self.last_activity {
            self.last_activity = now;
        }
    }

    /// True once the inactivity timeout has elapsed.
    pub fn should_lock(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.last_activity) >= self.timeout
    }

    /// Effective timeout.
    pub fn timeout(&self) -> Duration {
        self.timeout
    }
}

/// How long a copied secret may stay on the clipboard before it is cleared.
pub const CLIPBOARD_CLEAR_AFTER: Duration = Duration::from_secs(30);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_gate_fails_closed() {
        let g = FailClosedGate;
        assert!(!g.is_available());
        assert_eq!(g.authenticate("unlock"), Err(PlatformError::Unavailable));
    }

    #[test]
    fn locks_after_timeout_and_touch_resets() {
        let t0 = Instant::now();
        let mut a = AutoLock::new(Duration::from_secs(60), t0);
        assert!(!a.should_lock(t0 + Duration::from_secs(59)));
        assert!(a.should_lock(t0 + Duration::from_secs(60)));
        a.touch(t0 + Duration::from_secs(50));
        assert!(!a.should_lock(t0 + Duration::from_secs(100)));
        assert!(a.should_lock(t0 + Duration::from_secs(110)));
    }

    #[test]
    fn tiny_timeouts_are_clamped_and_clock_skew_is_safe() {
        let t0 = Instant::now();
        let mut a = AutoLock::new(Duration::ZERO, t0 + Duration::from_secs(10));
        assert_eq!(a.timeout(), AutoLock::MIN_TIMEOUT);
        assert!(!a.should_lock(t0));
        a.touch(t0);
        assert!(!a.should_lock(t0 + Duration::from_secs(11)));
    }
}
