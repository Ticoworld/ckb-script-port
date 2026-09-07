//! D2 v1 trusted-source exact-Script state handoff.
//!
//! The public product boundary is deliberately small: a canonical semantic
//! artifact, an adapter boundary for supported light-client storage profiles,
//! and export/inspect/validate/import operations.  The destination remains
//! authoritative for chain state; the source supplies only the typed
//! Script-derived view described by the artifact.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

#[cfg(all(feature = "rocksdb", feature = "sqlite"))]
compile_error!("choose exactly one native light-client storage backend feature");

mod artifact;
mod error;
mod limits;
mod operations;
mod upstream;

pub use artifact::{Artifact, ArtifactDigest, ArtifactInspection, Row, ScriptRole, FORMAT_VERSION};
pub use error::{D2Error, ErrorClass, Result};
pub use limits::ResourceLimits;
pub use operations::{
    DestinationAuthority, ExportedArtifact, ImportResult, StorageAdapter, ValidationReport, D2,
};
pub use upstream::{ProtocolActivityGuard, UpstreamAdapter, UPSTREAM_PROFILE};

#[cfg(feature = "rocksdb")]
pub use upstream::RocksDbStorage;

#[cfg(feature = "sqlite")]
pub use upstream::SqliteStorage;
