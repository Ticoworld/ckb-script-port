use std::fmt;

use thiserror::Error;

/// Whether an error represents a retryable environment problem or a
/// permanent artifact/contract rejection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorClass {
    /// The caller may retry after changing lifecycle, storage, or resources.
    Retryable,
    /// Retrying the same artifact and destination state cannot succeed.
    Permanent,
}

/// D2 product error categories.
#[derive(Debug, Error)]
pub enum D2Error {
    /// The artifact bytes do not have a valid D2 representation.
    #[error("malformed artifact: {0}")]
    MalformedArtifact(String),
    /// The artifact format version is not supported.
    #[error("unsupported artifact format version: {0}")]
    UnsupportedFormat(u32),
    /// The upstream adapter/profile is not supported by this build.
    #[error("unsupported storage profile: {0}")]
    UnsupportedProfile(String),
    /// The exact Script or role does not match the expected identity.
    #[error("identity mismatch: {0}")]
    IdentityMismatch(String),
    /// The artifact is bound to a different genesis.
    #[error("chain/genesis mismatch: {0}")]
    ChainGenesisMismatch(String),
    /// H or its block hash cannot be bound to destination authority.
    #[error("handoff mismatch: {0}")]
    HandoffMismatch(String),
    /// The Script-derived transaction closure is missing, malformed, or
    /// inconsistent.
    #[error("transaction closure failure: {0}")]
    ClosureFailure(String),
    /// Existing destination data conflicts with the artifact.
    #[error("destination conflict: {0}")]
    DestinationConflict(String),
    /// The destination has progressed beyond the artifact boundary.
    #[error("stale destination state: {0}")]
    StaleState(String),
    /// The destination is live or another operation owns the lifecycle.
    #[error("lifecycle/exclusivity failure: {0}")]
    Lifecycle(String),
    /// A native backend operation failed.
    #[error("storage failure: {0}")]
    Storage(String),
    /// The artifact exceeds a bounded product resource limit.
    #[error("resource limit: {0}")]
    ResourceLimit(String),
    /// A product invariant was violated by an adapter or upstream state.
    #[error("internal invariant violation: {0}")]
    Invariant(String),
}

impl D2Error {
    /// Classifies the error for caller retry decisions.
    pub fn class(&self) -> ErrorClass {
        match self {
            Self::Lifecycle(_) | Self::Storage(_) | Self::ResourceLimit(_) => ErrorClass::Retryable,
            Self::MalformedArtifact(_)
            | Self::UnsupportedFormat(_)
            | Self::UnsupportedProfile(_)
            | Self::IdentityMismatch(_)
            | Self::ChainGenesisMismatch(_)
            | Self::HandoffMismatch(_)
            | Self::ClosureFailure(_)
            | Self::DestinationConflict(_)
            | Self::StaleState(_)
            | Self::Invariant(_) => ErrorClass::Permanent,
        }
    }
}

/// Result type used by the D2 library.
pub type Result<T> = std::result::Result<T, D2Error>;

impl From<std::io::Error> for D2Error {
    fn from(error: std::io::Error) -> Self {
        Self::Storage(error.to_string())
    }
}

impl fmt::Display for ErrorClass {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Retryable => f.write_str("retryable"),
            Self::Permanent => f.write_str("permanent"),
        }
    }
}
