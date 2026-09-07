use crate::{
    Artifact, ArtifactDigest, ArtifactInspection, D2Error, ResourceLimits, Result, ScriptRole,
};

/// Destination-owned chain authority needed to accept a handoff.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DestinationAuthority {
    /// Destination genesis hash.
    pub genesis_hash: [u8; 32],
    /// Destination-recognized hash at the requested handoff height.
    pub handoff_hash: [u8; 32],
    /// Destination tip height.
    pub tip_height: u64,
}

/// Non-mutating validation result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationReport {
    /// Parsed artifact summary.
    pub artifact: ArtifactInspection,
    /// Destination authority used for validation.
    pub authority: DestinationAuthority,
    /// Whether the destination already contains complete identical state.
    pub idempotent: bool,
}

/// Result of a successful export.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExportedArtifact {
    /// Canonical artifact model.
    pub artifact: Artifact,
    /// Canonical encoded artifact bytes.
    pub bytes: Vec<u8>,
    /// Digest of the canonical artifact bytes excluding the trailing digest.
    pub digest: ArtifactDigest,
}

/// Result of a successful or idempotent import.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportResult {
    /// Imported exact Script bytes.
    pub script: Vec<u8>,
    /// Imported Script role.
    pub role: ScriptRole,
    /// Accepted handoff height.
    pub handoff_height: u64,
    /// Accepted handoff block hash.
    pub handoff_hash: [u8; 32],
    /// Artifact digest.
    pub digest: ArtifactDigest,
    /// Number of Script index rows in the artifact.
    pub index_rows: usize,
    /// Number of transaction-index rows in the artifact.
    pub transaction_index_rows: usize,
    /// Number of transaction closure rows in the artifact.
    pub transaction_rows: usize,
    /// Whether the destination already contained the accepted registration
    /// and identical state.
    pub idempotent: bool,
}

/// Storage adapter contract for D2 product operations.
pub trait StorageAdapter: Send + Sync {
    /// Returns the semantic upstream adapter/profile identifier.
    fn adapter_profile(&self) -> &str;

    /// Exports one exact Script and role from a quiescent source.
    fn export(&self, script: &[u8], role: ScriptRole, limits: &ResourceLimits) -> Result<Artifact>;

    /// Reads destination-owned chain authority without mutating storage.
    fn destination_authority(&self, handoff_height: u64) -> Result<DestinationAuthority>;

    /// Validates existing destination rows, lifecycle, and storage-specific
    /// invariants without mutation.
    fn validate_destination(&self, artifact: &Artifact, limits: &ResourceLimits) -> Result<bool>;

    /// Atomically commits an already validated artifact under the adapter's
    /// offline/exclusive lifecycle contract.
    fn import_atomically(
        &self,
        artifact: &Artifact,
        limits: &ResourceLimits,
    ) -> Result<ImportResult>;
}

/// D2 product operations over one supported storage adapter.
pub struct D2<A> {
    adapter: A,
    limits: ResourceLimits,
}

impl<A: StorageAdapter> D2<A> {
    /// Creates a product operation handle with bounded default limits.
    pub fn new(adapter: A) -> Self {
        Self {
            adapter,
            limits: ResourceLimits::default(),
        }
    }

    /// Creates a product operation handle with caller-selected safe limits.
    pub fn with_limits(adapter: A, limits: ResourceLimits) -> Self {
        Self { adapter, limits }
    }

    /// Returns the adapter/profile identifier.
    pub fn adapter_profile(&self) -> &str {
        self.adapter.adapter_profile()
    }

    /// Exports one exact Script and role to canonical bytes.
    pub fn export(&self, script: &[u8], role: ScriptRole) -> Result<ExportedArtifact> {
        let artifact = self.adapter.export(script, role, &self.limits)?;
        if artifact.adapter_profile != self.adapter.adapter_profile() {
            return Err(D2Error::UnsupportedProfile(artifact.adapter_profile));
        }
        if artifact.script != script || artifact.role != role {
            return Err(D2Error::IdentityMismatch(
                "adapter returned a different Script or role".into(),
            ));
        }
        artifact.validate(&self.limits)?;
        let bytes = artifact.encode(&self.limits)?;
        let digest = artifact.digest(&self.limits)?;
        Ok(ExportedArtifact {
            artifact,
            bytes,
            digest,
        })
    }

    /// Inspects and validates artifact bytes without opening or mutating a
    /// destination.
    pub fn inspect(&self, bytes: &[u8]) -> Result<ArtifactInspection> {
        Artifact::inspect(bytes, &self.limits)
    }

    /// Validates artifact bytes against destination authority and existing
    /// destination state without mutation.
    pub fn validate(&self, bytes: &[u8]) -> Result<ValidationReport> {
        let (artifact, _) = Artifact::decode(bytes, &self.limits)?;
        self.validate_model(&artifact)?;
        let authority = self
            .adapter
            .destination_authority(artifact.handoff_height)?;
        validate_authority(&artifact, authority)?;
        let idempotent = self.adapter.validate_destination(&artifact, &self.limits)?;
        let inspection = Artifact::inspect(bytes, &self.limits)?;
        Ok(ValidationReport {
            artifact: inspection,
            authority,
            idempotent,
        })
    }

    /// Validates and atomically imports artifact bytes.
    pub fn import(&self, bytes: &[u8]) -> Result<ImportResult> {
        let (artifact, digest) = Artifact::decode(bytes, &self.limits)?;
        self.validate_model(&artifact)?;
        let authority = self
            .adapter
            .destination_authority(artifact.handoff_height)?;
        validate_authority(&artifact, authority)?;
        self.adapter.validate_destination(&artifact, &self.limits)?;
        let mut result = self.adapter.import_atomically(&artifact, &self.limits)?;
        result.digest = digest;
        Ok(result)
    }

    /// Returns a reference to the underlying adapter for lifecycle integration.
    pub fn adapter(&self) -> &A {
        &self.adapter
    }

    fn validate_model(&self, artifact: &Artifact) -> Result<()> {
        if artifact.adapter_profile != self.adapter.adapter_profile() {
            return Err(D2Error::UnsupportedProfile(
                artifact.adapter_profile.clone(),
            ));
        }
        artifact.validate(&self.limits)
    }
}

fn validate_authority(artifact: &Artifact, authority: DestinationAuthority) -> Result<()> {
    if artifact.genesis_hash != authority.genesis_hash {
        return Err(D2Error::ChainGenesisMismatch(
            "artifact genesis differs from destination authority".into(),
        ));
    }
    if artifact.handoff_height > authority.tip_height {
        return Err(D2Error::HandoffMismatch(format!(
            "handoff height {} exceeds destination tip {}",
            artifact.handoff_height, authority.tip_height
        )));
    }
    if artifact.handoff_hash != authority.handoff_hash {
        return Err(D2Error::HandoffMismatch(
            "handoff hash differs from destination authority".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        sync::{Arc, Mutex},
    };

    use super::*;
    use crate::Row;

    const PROFILE: &str = "test-profile";

    #[derive(Default)]
    struct State {
        cursor: Option<u64>,
        rows: HashMap<Vec<u8>, Vec<u8>>,
        live: bool,
    }

    #[derive(Clone)]
    struct MemoryAdapter {
        artifact: Artifact,
        authority: DestinationAuthority,
        state: Arc<Mutex<State>>,
    }

    impl MemoryAdapter {
        fn new(artifact: Artifact) -> Self {
            let authority = DestinationAuthority {
                genesis_hash: artifact.genesis_hash,
                handoff_hash: artifact.handoff_hash,
                tip_height: artifact.handoff_height,
            };
            Self {
                artifact,
                authority,
                state: Arc::new(Mutex::new(State::default())),
            }
        }

        fn set_cursor(&self, cursor: u64) {
            self.state.lock().unwrap().cursor = Some(cursor);
        }

        fn set_live(&self, live: bool) {
            self.state.lock().unwrap().live = live;
        }
    }

    impl StorageAdapter for MemoryAdapter {
        fn adapter_profile(&self) -> &str {
            PROFILE
        }

        fn export(
            &self,
            script: &[u8],
            role: ScriptRole,
            _limits: &ResourceLimits,
        ) -> Result<Artifact> {
            if script != self.artifact.script || role != self.artifact.role {
                return Err(D2Error::IdentityMismatch("test identity mismatch".into()));
            }
            Ok(self.artifact.clone())
        }

        fn destination_authority(&self, _handoff_height: u64) -> Result<DestinationAuthority> {
            Ok(self.authority)
        }

        fn validate_destination(
            &self,
            artifact: &Artifact,
            _limits: &ResourceLimits,
        ) -> Result<bool> {
            let state = self.state.lock().unwrap();
            if state.live {
                return Err(D2Error::Lifecycle("test destination is live".into()));
            }
            if state.cursor.is_some_and(|cursor| cursor > artifact.cursor) {
                return Err(D2Error::StaleState("test destination is newer".into()));
            }
            let mut complete = true;
            for row in artifact
                .index_rows
                .iter()
                .chain(artifact.transaction_index_rows.iter())
                .chain(artifact.transaction_rows.iter())
            {
                match state.rows.get(&row.key) {
                    Some(value) if value != &row.value => {
                        return Err(D2Error::DestinationConflict("test row conflict".into()));
                    }
                    Some(_) => {}
                    None => complete = false,
                }
            }
            Ok(state.cursor == Some(artifact.cursor) && complete)
        }

        fn import_atomically(
            &self,
            artifact: &Artifact,
            limits: &ResourceLimits,
        ) -> Result<ImportResult> {
            let idempotent = self.validate_destination(artifact, limits)?;
            let mut state = self.state.lock().unwrap();
            for row in artifact
                .index_rows
                .iter()
                .chain(artifact.transaction_index_rows.iter())
                .chain(artifact.transaction_rows.iter())
            {
                state.rows.insert(row.key.clone(), row.value.clone());
            }
            state.cursor = Some(artifact.cursor);
            Ok(ImportResult {
                script: artifact.script.clone(),
                role: artifact.role,
                handoff_height: artifact.handoff_height,
                handoff_hash: artifact.handoff_hash,
                digest: artifact.digest(limits)?,
                index_rows: artifact.index_rows.len(),
                transaction_index_rows: artifact.transaction_index_rows.len(),
                transaction_rows: artifact.transaction_rows.len(),
                idempotent,
            })
        }
    }

    fn sample_artifact() -> Artifact {
        let tx_hash = [9u8; 32];
        Artifact {
            format_version: crate::FORMAT_VERSION,
            adapter_profile: PROFILE.into(),
            genesis_hash: [1u8; 32],
            script: vec![3, 4, 5],
            role: ScriptRole::Lock,
            handoff_height: 12,
            handoff_hash: [2u8; 32],
            cursor: 12,
            index_rows: vec![Row {
                key: vec![1],
                value: tx_hash.to_vec(),
            }],
            transaction_index_rows: vec![Row {
                key: vec![2],
                value: tx_hash.to_vec(),
            }],
            transaction_rows: vec![Row {
                key: std::iter::once(0).chain(tx_hash).collect(),
                value: vec![0; 12],
            }],
        }
    }

    #[test]
    fn public_lifecycle_exports_validates_imports_and_reimports() {
        let limits = ResourceLimits::default();
        let source = MemoryAdapter::new(sample_artifact());
        let destination = MemoryAdapter::new(sample_artifact());
        let source_d2 = D2::with_limits(source, limits);
        let destination_d2 = D2::with_limits(destination.clone(), limits);

        let exported = source_d2.export(&[3, 4, 5], ScriptRole::Lock).unwrap();
        let validation = destination_d2.validate(&exported.bytes).unwrap();
        assert!(!validation.idempotent);
        let imported = destination_d2.import(&exported.bytes).unwrap();
        assert!(!imported.idempotent);
        let repeated = destination_d2.import(&exported.bytes).unwrap();
        assert!(repeated.idempotent);
        assert_eq!(repeated.digest, exported.digest);
    }

    #[test]
    fn public_lifecycle_rejects_authority_conflict_stale_and_live_state() {
        let source_d2 = D2::new(MemoryAdapter::new(sample_artifact()));
        let exported = source_d2.export(&[3, 4, 5], ScriptRole::Lock).unwrap();

        let mut wrong_genesis = exported.artifact.clone();
        wrong_genesis.genesis_hash[0] ^= 1;
        let bytes = wrong_genesis.encode(&ResourceLimits::default()).unwrap();
        let destination = D2::new(MemoryAdapter::new(sample_artifact()));
        assert!(matches!(
            destination.import(&bytes),
            Err(D2Error::ChainGenesisMismatch(_))
        ));

        let stale_adapter = MemoryAdapter::new(sample_artifact());
        stale_adapter.set_cursor(99);
        let stale = D2::new(stale_adapter);
        assert!(matches!(
            stale.import(&exported.bytes),
            Err(D2Error::StaleState(_))
        ));

        let live_adapter = MemoryAdapter::new(sample_artifact());
        live_adapter.set_live(true);
        let live = D2::new(live_adapter);
        assert!(matches!(
            live.import(&exported.bytes),
            Err(D2Error::Lifecycle(_))
        ));
    }

    #[test]
    fn public_lifecycle_rejects_existing_conflict() {
        let source_d2 = D2::new(MemoryAdapter::new(sample_artifact()));
        let exported = source_d2.export(&[3, 4, 5], ScriptRole::Lock).unwrap();
        let destination_adapter = MemoryAdapter::new(sample_artifact());
        destination_adapter
            .state
            .lock()
            .unwrap()
            .rows
            .insert(vec![1], vec![0; 32]);
        let destination = D2::new(destination_adapter);
        assert!(matches!(
            destination.import(&exported.bytes),
            Err(D2Error::DestinationConflict(_))
        ));
    }
}
