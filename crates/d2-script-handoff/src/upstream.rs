use std::{
    collections::{BTreeSet, HashMap},
    panic::AssertUnwindSafe,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
};

#[cfg(test)]
use std::sync::atomic::{AtomicBool, Ordering};

use ckb_light_client_lib::storage::{
    BatchWriter, Key, KeyPrefix, LightClientStorage, ScriptType, StorageBackend,
};
use ckb_types::{packed, prelude::*};
use fs2::FileExt;
use std::fs::{File, OpenOptions};

use crate::{
    Artifact, D2Error, DestinationAuthority, ImportResult, ResourceLimits, Result, Row, ScriptRole,
    StorageAdapter,
};

/// The exact upstream semantic profile proved by RP2 and supported by G1.
pub const UPSTREAM_PROFILE: &str =
    "ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1";

#[cfg(feature = "rocksdb")]
/// Native RocksDB storage type from the supported upstream profile.
pub type RocksDbStorage = ckb_light_client_lib::storage::Storage;

#[cfg(feature = "sqlite")]
/// Native SQLite storage type from the supported upstream profile.
pub type SqliteStorage = ckb_light_client_lib::storage::Storage;

#[derive(Default)]
struct LifecycleState {
    active_protocol: usize,
}

struct Lifecycle {
    state: Mutex<LifecycleState>,
    lock_path: PathBuf,
    #[cfg(test)]
    fail_next_commit: AtomicBool,
}

static LIFECYCLES: OnceLock<Mutex<HashMap<PathBuf, Arc<Lifecycle>>>> = OnceLock::new();

fn lifecycle_for(path: &Path) -> Arc<Lifecycle> {
    let path = storage_identity_path(path);
    let map = LIFECYCLES.get_or_init(|| Mutex::new(HashMap::new()));
    let mut map = map.lock().expect("D2 lifecycle map is not poisoned");
    Arc::clone(map.entry(path.clone()).or_insert_with(|| {
        Arc::new(Lifecycle {
            state: Mutex::new(LifecycleState::default()),
            lock_path: path.with_extension("d2.lock"),
            #[cfg(test)]
            fail_next_commit: AtomicBool::new(false),
        })
    }))
}

fn storage_identity_path(path: &Path) -> PathBuf {
    #[cfg(feature = "sqlite")]
    let database_path = if path.is_dir() {
        path.join("db.sqlite")
    } else {
        path.to_path_buf()
    };
    #[cfg(not(feature = "sqlite"))]
    let database_path = path.to_path_buf();
    std::fs::canonicalize(&database_path).unwrap_or(database_path)
}

/// An RAII guard that marks protocol workers active for a destination path.
/// Import/export will fail while this guard is alive.
pub struct ProtocolActivityGuard {
    lifecycle: Arc<Lifecycle>,
    file: File,
}

impl Drop for ProtocolActivityGuard {
    fn drop(&mut self) {
        let _ = self.file.unlock();
        if let Ok(mut state) = self.lifecycle.state.lock() {
            state.active_protocol = state.active_protocol.saturating_sub(1);
        }
    }
}

struct ExclusiveGuard {
    file: Option<File>,
}

impl Drop for ExclusiveGuard {
    fn drop(&mut self) {
        if let Some(file) = self.file.as_ref() {
            let _ = file.unlock();
        }
    }
}

/// Adapter over the supported upstream `Storage` and `LightClientStorage`
/// traits. The type is generic so the same product code serves both native
/// backend feature builds.
pub struct UpstreamAdapter<S> {
    storage: Arc<S>,
    lifecycle: Arc<Lifecycle>,
    /// A lock acquired before opening native upstream storage.  This is used
    /// by the process-safe constructor so a competing RocksDB opener is
    /// rejected by D2 before it reaches the native database lock.
    preopened_exclusive: Arc<Mutex<Option<File>>>,
}

impl<S> Clone for UpstreamAdapter<S> {
    fn clone(&self) -> Self {
        Self {
            storage: Arc::clone(&self.storage),
            lifecycle: Arc::clone(&self.lifecycle),
            preopened_exclusive: Arc::clone(&self.preopened_exclusive),
        }
    }
}

impl<S> UpstreamAdapter<S>
where
    S: StorageBackend + LightClientStorage + Send + Sync + 'static,
{
    /// Wraps an already-open supported upstream storage instance.
    pub fn new(storage: S, path: impl AsRef<Path>) -> Self {
        Self {
            storage: Arc::new(storage),
            lifecycle: lifecycle_for(path.as_ref()),
            preopened_exclusive: Arc::new(Mutex::new(None)),
        }
    }

    /// Returns the shared upstream storage handle.
    pub fn storage(&self) -> &S {
        &self.storage
    }

    /// Marks protocol/filter/synchronizer activity as active. The guard must
    /// be held by integrated client workers while they can mutate storage.
    pub fn acquire_protocol_activity(&self) -> Result<ProtocolActivityGuard> {
        let mut state = self
            .lifecycle
            .state
            .lock()
            .map_err(|_| D2Error::Lifecycle("lifecycle mutex poisoned".into()))?;
        let file = open_lock_file(&self.lifecycle.lock_path)?;
        file.try_lock_shared().map_err(|error| {
            D2Error::Lifecycle(format!(
                "protocol activity could not acquire shared lock: {error}"
            ))
        })?;
        state.active_protocol += 1;
        Ok(ProtocolActivityGuard {
            lifecycle: Arc::clone(&self.lifecycle),
            file,
        })
    }

    fn acquire_exclusive(&self) -> Result<ExclusiveGuard> {
        {
            let state = self
                .lifecycle
                .state
                .lock()
                .map_err(|_| D2Error::Lifecycle("lifecycle mutex poisoned".into()))?;
            if state.active_protocol != 0 {
                return Err(D2Error::Lifecycle(
                    "destination has active protocol workers".into(),
                ));
            }
        }
        if self
            .preopened_exclusive
            .lock()
            .map_err(|_| D2Error::Lifecycle("lifecycle mutex poisoned".into()))?
            .is_some()
        {
            return Ok(ExclusiveGuard { file: None });
        }
        let file = open_lock_file(&self.lifecycle.lock_path)?;
        file.try_lock_exclusive().map_err(|error| {
            D2Error::Lifecycle(format!("destination is not exclusively offline: {error}"))
        })?;
        Ok(ExclusiveGuard { file: Some(file) })
    }

    #[cfg(test)]
    fn fail_next_commit_for_test(&self) {
        self.lifecycle
            .fail_next_commit
            .store(true, Ordering::SeqCst);
    }
}

impl UpstreamAdapter<ckb_light_client_lib::storage::Storage> {
    /// Opens the supported native upstream storage only after D2 has acquired
    /// the cross-process exclusive lifecycle lock.  Callers performing an
    /// import should use this constructor; opening RocksDB first would let a
    /// competing process fail inside the native engine before D2 can return a
    /// typed lifecycle error.
    pub fn open_exclusive(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let lifecycle = lifecycle_for(path);
        {
            let state = lifecycle
                .state
                .lock()
                .map_err(|_| D2Error::Lifecycle("lifecycle mutex poisoned".into()))?;
            if state.active_protocol != 0 {
                return Err(D2Error::Lifecycle(
                    "destination has active protocol workers".into(),
                ));
            }
        }
        let file = open_lock_file(&lifecycle.lock_path)?;
        file.try_lock_exclusive().map_err(|error| {
            D2Error::Lifecycle(format!("destination is not exclusively offline: {error}"))
        })?;
        let storage = std::panic::catch_unwind(AssertUnwindSafe(|| {
            ckb_light_client_lib::storage::Storage::new(path)
        }))
        .map_err(|_| D2Error::Storage("upstream native storage could not be opened".into()))?;
        Ok(Self {
            storage: Arc::new(storage),
            lifecycle,
            preopened_exclusive: Arc::new(Mutex::new(Some(file))),
        })
    }
}

impl<S> StorageAdapter for UpstreamAdapter<S>
where
    S: StorageBackend + LightClientStorage + Send + Sync + 'static,
{
    fn adapter_profile(&self) -> &str {
        UPSTREAM_PROFILE
    }

    fn export(
        &self,
        script_bytes: &[u8],
        role: ScriptRole,
        limits: &ResourceLimits,
    ) -> Result<Artifact> {
        let _exclusive = self.acquire_exclusive()?;
        let script = packed::Script::from_slice(script_bytes).map_err(|error| {
            D2Error::IdentityMismatch(format!("packed Script decode failed: {error:?}"))
        })?;
        let script_type = role_to_script_type(role);
        let status = self
            .storage
            .get_filter_scripts()
            .into_iter()
            .find(|status| {
                status.script.as_slice() == script_bytes && status.script_type == script_type
            })
            .ok_or_else(|| {
                D2Error::IdentityMismatch("exact Script+role is not registered".into())
            })?;
        let handoff_height = status.block_number;
        let genesis_hash = read_genesis_hash(self.storage.as_ref())?;
        let handoff_hash = read_block_hash(self.storage.as_ref(), handoff_height)?;
        let (index_rows, transaction_index_rows, transaction_rows) =
            collect_rows(self.storage.as_ref(), &script, role, limits)?;
        let artifact = Artifact {
            format_version: crate::FORMAT_VERSION,
            adapter_profile: UPSTREAM_PROFILE.to_owned(),
            genesis_hash,
            script: script_bytes.to_vec(),
            role,
            handoff_height,
            handoff_hash,
            cursor: status.block_number,
            index_rows,
            transaction_index_rows,
            transaction_rows,
        };
        artifact.validate(limits)?;
        Ok(artifact)
    }

    fn destination_authority(&self, handoff_height: u64) -> Result<DestinationAuthority> {
        let genesis_hash = read_genesis_hash(self.storage.as_ref())?;
        let handoff_hash = read_block_hash(self.storage.as_ref(), handoff_height)?;
        let tip_height = read_tip_height(self.storage.as_ref())?;
        Ok(DestinationAuthority {
            genesis_hash,
            handoff_hash,
            tip_height,
        })
    }

    fn validate_destination(&self, artifact: &Artifact, limits: &ResourceLimits) -> Result<bool> {
        let _ = limits;
        if artifact.adapter_profile != UPSTREAM_PROFILE {
            return Err(D2Error::UnsupportedProfile(
                artifact.adapter_profile.clone(),
            ));
        }
        validate_upstream_rows(artifact)?;
        let existing = exact_status(self.storage.as_ref(), &artifact.script, artifact.role)?;
        if let Some(status) = existing {
            if status > artifact.cursor {
                return Err(D2Error::StaleState(format!(
                    "destination cursor {status} exceeds artifact cursor {}",
                    artifact.cursor
                )));
            }
        }
        let all_rows_present = check_existing_rows(self.storage.as_ref(), artifact)?;
        Ok(existing == Some(artifact.cursor) && all_rows_present)
    }

    fn import_atomically(
        &self,
        artifact: &Artifact,
        limits: &ResourceLimits,
    ) -> Result<ImportResult> {
        let _exclusive = self.acquire_exclusive()?;
        artifact.validate(limits)?;
        if artifact.adapter_profile != UPSTREAM_PROFILE {
            return Err(D2Error::UnsupportedProfile(
                artifact.adapter_profile.clone(),
            ));
        }
        validate_authority_against_storage(self.storage.as_ref(), artifact)?;
        validate_upstream_rows(artifact)?;
        let already_present = self.validate_destination(artifact, limits)?;
        let mut batch = self.storage.batch();
        for row in artifact
            .index_rows
            .iter()
            .chain(artifact.transaction_index_rows.iter())
            .chain(artifact.transaction_rows.iter())
        {
            if backend_get(self.storage.as_ref(), row.key.clone())?.is_none() {
                batch.put(&row.key, &row.value);
            }
        }
        let script = packed::Script::from_slice(&artifact.script).map_err(|error| {
            D2Error::IdentityMismatch(format!("packed Script decode failed: {error:?}"))
        })?;
        let script_key = filter_script_key(&script, artifact.role);
        let current = exact_status(self.storage.as_ref(), &artifact.script, artifact.role)?;
        if current != Some(artifact.cursor) {
            batch.put(&script_key, &artifact.cursor.to_be_bytes());
        }
        let imported_script_type = role_to_script_type(artifact.role);
        let min = self
            .storage
            .get_filter_scripts()
            .into_iter()
            .filter(|status| {
                !(status.script.as_slice() == artifact.script.as_slice()
                    && status.script_type == imported_script_type)
            })
            .map(|status| status.block_number)
            .chain(std::iter::once(artifact.cursor))
            .min()
            .expect("imported cursor supplies a non-empty minimum");
        batch.put(
            &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
            &min.to_le_bytes(),
        );
        #[cfg(test)]
        if self
            .lifecycle
            .fail_next_commit
            .swap(false, Ordering::SeqCst)
        {
            return Err(D2Error::Storage(
                "injected failure before native batch commit".into(),
            ));
        }
        #[cfg(test)]
        pause_before_commit_for_test()?;
        batch
            .commit()
            .map_err(|error| D2Error::Storage(format!("native batch commit failed: {error:?}")))?;
        verify_imported_state(self.storage.as_ref(), artifact)?;
        Ok(ImportResult {
            script: artifact.script.clone(),
            role: artifact.role,
            handoff_height: artifact.handoff_height,
            handoff_hash: artifact.handoff_hash,
            digest: artifact.digest(limits)?,
            index_rows: artifact.index_rows.len(),
            transaction_index_rows: artifact.transaction_index_rows.len(),
            transaction_rows: artifact.transaction_rows.len(),
            idempotent: already_present,
        })
    }
}

fn verify_imported_state<S>(storage: &S, artifact: &Artifact) -> Result<()>
where
    S: StorageBackend + LightClientStorage,
{
    for row in artifact
        .index_rows
        .iter()
        .chain(artifact.transaction_index_rows.iter())
        .chain(artifact.transaction_rows.iter())
    {
        if backend_get(storage, row.key.clone())?.as_deref() != Some(row.value.as_slice()) {
            return Err(D2Error::Storage(
                "committed artifact row failed post-commit verification".into(),
            ));
        }
    }
    if exact_status(storage, &artifact.script, artifact.role)? != Some(artifact.cursor) {
        return Err(D2Error::Storage(
            "committed Script cursor failed post-commit verification".into(),
        ));
    }
    Ok(())
}

fn validate_authority_against_storage<S>(storage: &S, artifact: &Artifact) -> Result<()>
where
    S: StorageBackend,
{
    let genesis_hash = read_genesis_hash(storage)?;
    if artifact.genesis_hash != genesis_hash {
        return Err(D2Error::ChainGenesisMismatch(
            "artifact genesis differs from destination authority".into(),
        ));
    }
    let handoff_hash = read_block_hash(storage, artifact.handoff_height)?;
    if artifact.handoff_hash != handoff_hash {
        return Err(D2Error::HandoffMismatch(
            "artifact handoff hash differs from destination authority".into(),
        ));
    }
    let tip_height = read_tip_height(storage)?;
    if artifact.handoff_height > tip_height {
        return Err(D2Error::HandoffMismatch(format!(
            "handoff height {} exceeds destination tip {}",
            artifact.handoff_height, tip_height
        )));
    }
    Ok(())
}

fn open_lock_file(path: &Path) -> Result<File> {
    OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(path)
        .map_err(|error| D2Error::Lifecycle(format!("open lifecycle lock failed: {error}")))
}

fn role_to_script_type(role: ScriptRole) -> ScriptType {
    match role {
        ScriptRole::Lock => ScriptType::Lock,
        ScriptRole::Type => ScriptType::Type,
    }
}

fn role_prefix(role: ScriptRole) -> (u8, u8) {
    match role {
        ScriptRole::Lock => (
            KeyPrefix::CellLockScript as u8,
            KeyPrefix::TxLockScript as u8,
        ),
        ScriptRole::Type => (
            KeyPrefix::CellTypeScript as u8,
            KeyPrefix::TxTypeScript as u8,
        ),
    }
}

fn script_raw_prefix(script: &packed::Script, prefix: u8) -> Vec<u8> {
    let mut key = vec![prefix];
    key.extend_from_slice(&ckb_light_client_lib::storage::extract_raw_data(script));
    key
}

fn filter_script_key(script: &packed::Script, role: ScriptRole) -> Vec<u8> {
    let mut key = Key::Meta("FILTER_SCRIPTS").into_vec();
    key.extend_from_slice(script.as_slice());
    key.push(match role {
        ScriptRole::Lock => 0,
        ScriptRole::Type => 1,
    });
    key
}

fn collect_rows<S>(
    storage: &S,
    script: &packed::Script,
    role: ScriptRole,
    limits: &ResourceLimits,
) -> Result<(Vec<Row>, Vec<Row>, Vec<Row>)>
where
    S: StorageBackend + LightClientStorage,
{
    let (cell_prefix_byte, tx_prefix_byte) = role_prefix(role);
    let cell_prefix = script_raw_prefix(script, cell_prefix_byte);
    let tx_prefix = script_raw_prefix(script, tx_prefix_byte);
    let index_rows = collect_prefix(storage, &cell_prefix, limits.max_rows_per_section)?;
    let transaction_index_rows = collect_prefix(storage, &tx_prefix, limits.max_rows_per_section)?;
    validate_index_rows(&index_rows, &cell_prefix, 16)?;
    validate_index_rows(&transaction_index_rows, &tx_prefix, 17)?;
    let hashes = index_rows
        .iter()
        .chain(transaction_index_rows.iter())
        .map(|row| {
            if row.value.len() != 32 {
                return Err(D2Error::ClosureFailure(
                    "Script index value is not a transaction hash".into(),
                ));
            }
            let mut hash = [0u8; 32];
            hash.copy_from_slice(&row.value);
            Ok(hash)
        })
        .collect::<Result<BTreeSet<_>>>()?;
    let mut transaction_rows = Vec::with_capacity(hashes.len());
    for hash in hashes {
        let key = Key::TxHash(&packed::Byte32::from_slice(&hash).map_err(|error| {
            D2Error::ClosureFailure(format!("transaction hash decode failed: {error:?}"))
        })?)
        .into_vec();
        let value = backend_get(storage, key.clone())?
            .ok_or_else(|| D2Error::ClosureFailure("referenced transaction is missing".into()))?;
        validate_transaction_value(&key, &value)?;
        transaction_rows.push(Row { key, value });
    }
    transaction_rows.sort_by(|left, right| left.key.cmp(&right.key));
    Ok((index_rows, transaction_index_rows, transaction_rows))
}

fn collect_prefix<S>(storage: &S, prefix: &[u8], limit: usize) -> Result<Vec<Row>>
where
    S: StorageBackend,
{
    let start = prefix.to_vec();
    let take = prefix.to_vec();
    let rows = storage.collect_iterator(
        ckb_light_client_lib::storage::IteratorStart::From(start),
        ckb_light_client_lib::storage::IteratorDirection::Forward,
        Box::new(move |key| key.starts_with(&take)),
        Box::new(|_key, value| Some(value.to_vec())),
        limit.saturating_add(1),
    );
    if rows.len() > limit {
        return Err(D2Error::ResourceLimit(format!(
            "Script index rows exceed limit {limit}"
        )));
    }
    let mut output = rows
        .into_iter()
        .map(|row| Row {
            key: row.key,
            value: row.value,
        })
        .collect::<Vec<_>>();
    output.sort_by(|left, right| left.key.cmp(&right.key));
    Ok(output)
}

fn validate_index_rows(rows: &[Row], prefix: &[u8], suffix_len: usize) -> Result<()> {
    for row in rows {
        if row.key.len() != prefix.len() + suffix_len || !row.key.starts_with(prefix) {
            return Err(D2Error::Invariant(
                "upstream Script index key has unexpected shape".into(),
            ));
        }
        if row.value.len() != 32 {
            return Err(D2Error::ClosureFailure(
                "upstream Script index value has unexpected shape".into(),
            ));
        }
    }
    Ok(())
}

fn validate_transaction_value(key: &[u8], value: &[u8]) -> Result<()> {
    if key.len() != 33 || key[0] != KeyPrefix::TxHash as u8 || value.len() < 12 {
        return Err(D2Error::ClosureFailure(
            "upstream transaction row has unexpected shape".into(),
        ));
    }
    let transaction = packed::Transaction::from_slice(&value[12..]).map_err(|error| {
        D2Error::ClosureFailure(format!("transaction decode failed: {error:?}"))
    })?;
    if transaction.calc_tx_hash().as_slice() != &key[1..] {
        return Err(D2Error::ClosureFailure(
            "transaction key does not match transaction value".into(),
        ));
    }
    Ok(())
}

fn validate_upstream_rows(artifact: &Artifact) -> Result<()> {
    let script = packed::Script::from_slice(&artifact.script).map_err(|error| {
        D2Error::IdentityMismatch(format!("packed Script decode failed: {error:?}"))
    })?;
    let (cell_prefix_byte, tx_prefix_byte) = role_prefix(artifact.role);
    let cell_prefix = script_raw_prefix(&script, cell_prefix_byte);
    let tx_prefix = script_raw_prefix(&script, tx_prefix_byte);
    validate_index_rows(&artifact.index_rows, &cell_prefix, 16)?;
    validate_index_rows(&artifact.transaction_index_rows, &tx_prefix, 17)?;
    for row in &artifact.transaction_rows {
        validate_transaction_value(&row.key, &row.value)?;
    }
    for row in artifact
        .index_rows
        .iter()
        .chain(artifact.transaction_index_rows.iter())
        .chain(artifact.transaction_rows.iter())
    {
        if row.key.first().copied().unwrap_or_default() >= KeyPrefix::BlockHash as u8 {
            return Err(D2Error::IdentityMismatch(
                "artifact contains a forbidden authority/global row".into(),
            ));
        }
    }
    Ok(())
}

fn exact_status<S>(storage: &S, script: &[u8], role: ScriptRole) -> Result<Option<u64>>
where
    S: LightClientStorage,
{
    Ok(storage
        .get_filter_scripts()
        .into_iter()
        .find(|status| {
            status.script.as_slice() == script && status.script_type == role_to_script_type(role)
        })
        .map(|status| status.block_number))
}

fn check_existing_rows<S>(storage: &S, artifact: &Artifact) -> Result<bool>
where
    S: StorageBackend,
{
    let mut all_present = true;
    for row in artifact
        .index_rows
        .iter()
        .chain(artifact.transaction_index_rows.iter())
        .chain(artifact.transaction_rows.iter())
    {
        match backend_get(storage, row.key.clone())? {
            Some(existing) if existing != row.value => {
                return Err(D2Error::DestinationConflict(
                    "existing row value differs from artifact".into(),
                ));
            }
            Some(_) => {}
            None => all_present = false,
        }
    }
    Ok(all_present)
}

fn read_genesis_hash<S>(storage: &S) -> Result<[u8; 32]>
where
    S: StorageBackend,
{
    let key = Key::Meta("GENESIS_BLOCK").into_vec();
    let value = backend_get(storage, key)?
        .ok_or_else(|| D2Error::Storage("destination genesis is not initialized".into()))?;
    if value.len() < 32 {
        return Err(D2Error::Storage(
            "stored genesis metadata is truncated".into(),
        ));
    }
    Ok(value[..32].try_into().unwrap())
}

fn read_block_hash<S>(storage: &S, height: u64) -> Result<[u8; 32]>
where
    S: StorageBackend,
{
    if let Some(value) = backend_get(storage, Key::BlockNumber(height).into_vec())? {
        if value.len() != 32 {
            return Err(D2Error::HandoffMismatch(
                "stored block hash has invalid length".into(),
            ));
        }
        return Ok(value.try_into().unwrap());
    }

    // The live pinned light-client proof path may retain the accepted tip in
    // LAST_STATE without retaining a full BlockNumber index for that height.
    // A handoff at the destination's current tip can therefore use the
    // independently stored LAST_STATE header as its authority fact.  This
    // fallback is deliberately limited to the matching tip height; it does
    // not make source headers authoritative or reconstruct arbitrary history.
    let last_state = backend_get(
        storage,
        Key::Meta(ckb_light_client_lib::storage::LAST_STATE_KEY).into_vec(),
    )?
    .ok_or_else(|| {
        D2Error::HandoffMismatch(format!("destination has no block hash at height {height}"))
    })?;
    if last_state.len() < 32 + packed::Header::TOTAL_SIZE {
        return Err(D2Error::HandoffMismatch(
            "stored last state is truncated".into(),
        ));
    }
    let header = packed::Header::from_slice(&last_state[32..]).map_err(|error| {
        D2Error::HandoffMismatch(format!("stored last state is invalid: {error:?}"))
    })?;
    let header_height: u64 = header.raw().number().unpack();
    if header_height != height {
        return Err(D2Error::HandoffMismatch(format!(
            "destination has no block hash at height {height}"
        )));
    }
    Ok(header.calc_header_hash().as_slice().try_into().unwrap())
}

fn read_tip_height<S>(storage: &S) -> Result<u64>
where
    S: StorageBackend,
{
    let value = backend_get(
        storage,
        Key::Meta(ckb_light_client_lib::storage::LAST_STATE_KEY).into_vec(),
    )?
    .ok_or_else(|| D2Error::Storage("destination last state is not initialized".into()))?;
    if value.len() < 32 + packed::Header::TOTAL_SIZE {
        return Err(D2Error::Storage("stored last state is truncated".into()));
    }
    let header = packed::Header::from_slice(&value[32..])
        .map_err(|error| D2Error::Storage(format!("stored last header is invalid: {error:?}")))?;
    Ok(header.raw().number().unpack())
}

fn backend_get<S>(storage: &S, key: Vec<u8>) -> Result<Option<Vec<u8>>>
where
    S: StorageBackend,
{
    StorageBackend::get(storage, key)
        .map_err(|error| D2Error::Storage(format!("upstream read failed: {error:?}")))
}

#[cfg(test)]
fn pause_before_commit_for_test() -> Result<()> {
    let Some(ready_path) = std::env::var_os("D2_TEST_PAUSE_BEFORE_COMMIT") else {
        return Ok(());
    };
    let Some(release_path) = std::env::var_os("D2_TEST_RELEASE_COMMIT") else {
        return Err(D2Error::Invariant(
            "D2_TEST_PAUSE_BEFORE_COMMIT requires D2_TEST_RELEASE_COMMIT".into(),
        ));
    };
    std::fs::write(&ready_path, b"prepared\n").map_err(|error| {
        D2Error::Storage(format!("write test commit-ready marker failed: {error}"))
    })?;
    while !std::path::Path::new(&release_path).exists() {
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    Ok(())
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use ckb_light_client_lib::storage::{BatchWriter, CellType, Storage, Value};
    use ckb_types::packed;
    use tempfile::tempdir;

    fn g1_required_env(name: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| panic!("missing {name} environment variable"))
    }

    fn g1_decode_hex(value: &str) -> Vec<u8> {
        let value = value.strip_prefix("0x").unwrap_or(value);
        assert!(value.len().is_multiple_of(2), "hex value has odd length");
        (0..value.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&value[index..index + 2], 16).expect("valid hex"))
            .collect()
    }

    fn g1_hex(value: &[u8]) -> String {
        let mut output = String::from("0x");
        for byte in value {
            output.push_str(&format!("{byte:02x}"));
        }
        output
    }

    fn g1_json_string(value: &str) -> String {
        let mut escaped = String::from("\"");
        for character in value.chars() {
            match character {
                '\\' => escaped.push_str("\\\\"),
                '"' => escaped.push_str("\\\""),
                '\n' => escaped.push_str("\\n"),
                '\r' => escaped.push_str("\\r"),
                '\t' => escaped.push_str("\\t"),
                character if character.is_control() => {
                    escaped.push_str(&format!("\\u{:04x}", character as u32))
                }
                character => escaped.push(character),
            }
        }
        escaped.push('"');
        escaped
    }

    fn g1_worker_result(value: &str) {
        let path = std::path::PathBuf::from(g1_required_env("D2_G1_WORKER_RESULT"));
        std::fs::write(path, value).expect("write worker result");
    }

    /// Test-only process worker. Every operation below goes through the
    /// public production D2 facade and the native upstream adapter; the
    /// worker exists so PowerShell runners can exercise real process
    /// boundaries without adding a product CLI.
    #[test]
    #[ignore = "invoked by G1-R1 process runners"]
    fn production_g1_external_worker() {
        let mode = g1_required_env("D2_G1_MODE");
        if mode == "race-prepare" {
            let source_path = std::path::PathBuf::from(g1_required_env("D2_G1_SOURCE"));
            let (source, script) = fixture_storage(&source_path, true);
            drop(source);
            let source = Storage::new(&source_path);
            let exported = crate::D2::new(UpstreamAdapter::new(source, &source_path))
                .export(&script, ScriptRole::Lock)
                .expect("prepare race artifact");
            let destination_path = std::path::PathBuf::from(g1_required_env("D2_G1_STORAGE"));
            let _destination = fixture_storage(&destination_path, false).0;
            let artifact_path = std::path::PathBuf::from(g1_required_env("D2_G1_ARTIFACT"));
            std::fs::write(&artifact_path, &exported.bytes).expect("write race artifact");
            g1_worker_result(&format!(
                "{{\"mode\":{},\"profile\":{},\"artifact_bytes\":{},\"handoff_height\":{}}}",
                g1_json_string(&mode),
                g1_json_string(UPSTREAM_PROFILE),
                exported.bytes.len(),
                exported.artifact.handoff_height,
            ));
            return;
        }
        let path = std::path::PathBuf::from(g1_required_env("D2_G1_STORAGE"));
        let adapter = if mode == "import" || mode == "race-import" {
            match UpstreamAdapter::open_exclusive(&path) {
                Ok(adapter) => adapter,
                Err(error) => {
                    g1_worker_result(&format!(
                        "{{\"mode\":{},\"process_id\":{},\"outcome\":\"rejected\",\"class\":{},\"error\":{}}}",
                        g1_json_string(&mode),
                        std::process::id(),
                        g1_json_string(&format!("{:?}", error.class())),
                        g1_json_string(&error.to_string()),
                    ));
                    return;
                }
            }
        } else {
            let storage = Storage::new(&path);
            UpstreamAdapter::new(storage, &path)
        };
        let d2 = crate::D2::new(adapter);
        match mode.as_str() {
            "export" => {
                let script = g1_decode_hex(&g1_required_env("D2_G1_SCRIPT"));
                let exported = d2
                    .export(&script, ScriptRole::Lock)
                    .expect("production D2 export");
                let artifact_path = std::path::PathBuf::from(g1_required_env("D2_G1_ARTIFACT"));
                std::fs::write(&artifact_path, &exported.bytes).expect("write D2 artifact");
                g1_worker_result(&format!(
                    "{{\"mode\":{},\"profile\":{},\"artifact_bytes\":{},\"handoff_height\":{},\"digest\":{}}}",
                    g1_json_string(&mode),
                    g1_json_string(UPSTREAM_PROFILE),
                    exported.bytes.len(),
                    exported.artifact.handoff_height,
                    g1_json_string(&g1_hex(&exported.digest.0)),
                ));
            }
            "import" | "race-import" => {
                let artifact_path = std::path::PathBuf::from(g1_required_env("D2_G1_ARTIFACT"));
                let bytes = std::fs::read(&artifact_path).expect("read D2 artifact");
                let outcome = d2.import(&bytes);
                let result = match outcome {
                    Ok(result) => format!(
                        "{{\"mode\":{},\"process_id\":{},\"outcome\":\"accepted\",\"idempotent\":{},\"handoff_height\":{},\"digest\":{}}}",
                        g1_json_string(&mode),
                        std::process::id(),
                        result.idempotent,
                        result.handoff_height,
                        g1_json_string(&g1_hex(&result.digest.0)),
                    ),
                    Err(error) => format!(
                        "{{\"mode\":{},\"process_id\":{},\"outcome\":\"rejected\",\"class\":{},\"error\":{}}}",
                        g1_json_string(&mode),
                        std::process::id(),
                        g1_json_string(&format!("{:?}", error.class())),
                        g1_json_string(&error.to_string()),
                    ),
                };
                g1_worker_result(&result);
            }
            other => panic!("unknown D2_G1_MODE {other}"),
        }
    }

    #[derive(Clone, Copy)]
    struct G2Workload {
        name: &'static str,
        class: &'static str,
        history_depth: u64,
        match_stride: u64,
        transactions_per_match: u32,
        outputs_per_transaction: u32,
    }

    fn g2_workload(name: &str) -> G2Workload {
        match name {
            "control" => G2Workload {
                name: "control",
                class: "CONTROL",
                history_depth: 36,
                match_stride: 18,
                transactions_per_match: 1,
                outputs_per_transaction: 1,
            },
            "realistic-sparse" => G2Workload {
                name: "realistic-sparse",
                class: "REALISTIC-SYNTHETIC",
                history_depth: 10_000,
                match_stride: 100,
                transactions_per_match: 1,
                outputs_per_transaction: 1,
            },
            "realistic-moderate" => G2Workload {
                name: "realistic-moderate",
                class: "REALISTIC-SYNTHETIC",
                history_depth: 5_000,
                match_stride: 10,
                transactions_per_match: 2,
                outputs_per_transaction: 4,
            },
            "realistic-dense" => G2Workload {
                name: "realistic-dense",
                class: "REALISTIC-SYNTHETIC",
                history_depth: 2_000,
                match_stride: 1,
                transactions_per_match: 2,
                outputs_per_transaction: 4,
            },
            "stress-unique" => G2Workload {
                name: "stress-unique",
                class: "STRESS",
                history_depth: 2_500,
                match_stride: 1,
                transactions_per_match: 4,
                outputs_per_transaction: 2,
            },
            "stress-shared" => G2Workload {
                name: "stress-shared",
                class: "STRESS",
                history_depth: 2_500,
                match_stride: 1,
                transactions_per_match: 1,
                outputs_per_transaction: 16,
            },
            other => panic!("unknown G2 workload {other}"),
        }
    }

    fn g2_required_env(name: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| panic!("missing {name} environment variable"))
    }

    fn g2_json_array(values: &[u128]) -> String {
        format!(
            "[{}]",
            values
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(",")
        )
    }

    fn g2_result(value: &str) {
        let path = std::path::PathBuf::from(g2_required_env("D2_G2_OUTPUT"));
        std::fs::write(path, value).expect("write G2 worker result");
    }

    fn g2_tree_bytes(path: &Path) -> u64 {
        if path.is_file() {
            return path.metadata().map(|metadata| metadata.len()).unwrap_or(0);
        }
        let Ok(entries) = std::fs::read_dir(path) else {
            return 0;
        };
        entries
            .filter_map(|entry| entry.ok())
            .map(|entry| {
                let path = entry.path();
                if path.is_dir() {
                    g2_tree_bytes(&path)
                } else {
                    entry.metadata().map(|metadata| metadata.len()).unwrap_or(0)
                }
            })
            .sum()
    }

    fn g2_script(seed: u8) -> packed::Script {
        packed::Script::new_builder()
            .code_hash(packed::Byte32::from_slice(&[seed; 32]).unwrap())
            .build()
    }

    fn g2_header(number: u64) -> packed::Header {
        packed::Header::new_builder()
            .raw(
                packed::RawHeader::new_builder()
                    .number(number)
                    .timestamp(1_000u64 + number)
                    .build(),
            )
            .build()
    }

    fn g2_transaction(
        script: &packed::Script,
        transaction_number: u64,
        outputs_per_transaction: u32,
    ) -> packed::Transaction {
        let outputs = (0..outputs_per_transaction)
            .map(|output_index| {
                packed::CellOutput::new_builder()
                    .capacity(100 + transaction_number * 32 + output_index as u64)
                    .lock(script.clone())
                    .build()
            })
            .collect::<Vec<_>>();
        packed::Transaction::new_builder()
            .raw(
                packed::RawTransaction::new_builder()
                    .outputs(outputs.pack())
                    .build(),
            )
            .build()
    }

    fn g2_block(number: u64, transactions: Vec<packed::Transaction>) -> packed::Block {
        packed::Block::new_builder()
            .header(g2_header(number))
            .transactions(transactions.pack())
            .build()
    }

    fn g2_init_base(path: &Path) -> (Storage, packed::Script) {
        let storage = Storage::new(path);
        let genesis = packed::Block::new_builder().header(g2_header(0)).build();
        storage.init_genesis_block(genesis);
        (storage, g2_script(7))
    }

    fn g2_register(storage: &Storage, script: &packed::Script, cursor: u64) {
        let key = filter_script_key(script, ScriptRole::Lock);
        let mut batch = storage.batch();
        batch.put(&key, &cursor.to_be_bytes());
        batch.put(
            &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
            &cursor.to_le_bytes(),
        );
        batch.commit().expect("register G2 Script");
    }

    fn g2_set_authority(storage: &Storage, script: &packed::Script, spec: G2Workload) {
        let header = g2_header(spec.history_depth);
        let hash = header.calc_header_hash();
        let mut last_state = vec![0u8; 32];
        last_state.extend_from_slice(header.as_slice());
        let mut batch = storage.batch();
        batch.put(&Key::BlockHash(&hash).into_vec(), header.as_slice());
        batch.put(
            &Key::BlockNumber(spec.history_depth).into_vec(),
            hash.as_slice(),
        );
        batch.put(
            &Key::Meta(ckb_light_client_lib::storage::LAST_STATE_KEY).into_vec(),
            &last_state,
        );
        batch.put(
            &filter_script_key(script, ScriptRole::Lock),
            &spec.history_depth.to_be_bytes(),
        );
        batch.put(
            &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
            &spec.history_depth.to_le_bytes(),
        );
        batch.commit().expect("set G2 authority");
    }

    fn g2_apply_history(storage: &Storage, script: &packed::Script, spec: G2Workload) {
        let mut transaction_number = 0u64;
        for block_number in 1..=spec.history_depth {
            let transactions = if block_number % spec.match_stride == 0 {
                (0..spec.transactions_per_match)
                    .map(|_| {
                        let transaction = g2_transaction(
                            script,
                            transaction_number,
                            spec.outputs_per_transaction,
                        );
                        transaction_number += 1;
                        transaction
                    })
                    .collect()
            } else {
                Vec::new()
            };
            storage.filter_block(g2_block(block_number, transactions));
        }
        g2_set_authority(storage, script, spec);
    }

    fn g2_prepare_source(path: &Path, spec: G2Workload) -> (packed::Script, u128) {
        let started = std::time::Instant::now();
        let (storage, script) = g2_init_base(path);
        g2_register(&storage, &script, 0);
        g2_apply_history(&storage, &script, spec);
        drop(storage);
        (script, started.elapsed().as_micros())
    }

    fn g2_prepare_destination(path: &Path, spec: G2Workload) {
        let (storage, script) = g2_init_base(path);
        g2_set_authority(&storage, &script, spec);
        drop(storage);
    }

    fn g2_run_rescan(path: &Path, spec: G2Workload) -> (u128, packed::Script) {
        let started = std::time::Instant::now();
        let (storage, script) = g2_init_base(path);
        g2_register(&storage, &script, 0);
        g2_apply_history(&storage, &script, spec);
        drop(storage);
        (started.elapsed().as_micros(), script)
    }

    /// Test-only G2 scale worker. The generated workloads use the pinned
    /// upstream native storage profile and call its real filter_block path;
    /// they are synthetic chain histories, not mainnet data. All handoff
    /// operations in this worker use the public production D2 facade.
    #[test]
    #[ignore = "invoked by G2 scale runners"]
    fn g2_scale_worker() {
        let mode = g2_required_env("D2_G2_MODE");
        let spec = g2_workload(&g2_required_env("D2_G2_WORKLOAD"));
        let path = std::path::PathBuf::from(g2_required_env("D2_G2_PATH"));
        let repeats = g2_required_env("D2_G2_REPEATS")
            .parse::<usize>()
            .expect("valid G2 repeat count");
        assert!(repeats > 0 && repeats <= 10, "bounded G2 repeat count");

        match mode.as_str() {
            "export" => {
                let (script, preparation_us) = g2_prepare_source(&path, spec);
                let adapter = UpstreamAdapter::open_exclusive(&path).expect("open G2 source");
                let d2 = crate::D2::new(adapter);
                let mut export_us = Vec::with_capacity(repeats);
                let mut artifact = None;
                for _ in 0..repeats {
                    let started = std::time::Instant::now();
                    let exported = d2
                        .export(script.as_slice(), ScriptRole::Lock)
                        .expect("production G2 export");
                    export_us.push(started.elapsed().as_micros());
                    artifact = Some(exported);
                }
                let exported = artifact.expect("G2 export result");
                let artifact_path = std::path::PathBuf::from(g2_required_env("D2_G2_ARTIFACT"));
                std::fs::write(&artifact_path, &exported.bytes).expect("write G2 artifact");
                g2_result(&format!(
                    "{{\"mode\":\"export\",\"workload\":\"{}\",\"class\":\"{}\",\"backend\":\"{}\",\"history_depth\":{},\"match_stride\":{},\"expected_matched_blocks\":{},\"expected_index_rows\":{},\"expected_transaction_rows\":{},\"preparation_us\":{},\"export_us\":{},\"source_bytes\":{},\"artifact_bytes\":{},\"row_payload_bytes\":{},\"index_rows\":{},\"transaction_index_rows\":{},\"transaction_rows\":{},\"handoff_height\":{},\"digest\":\"{}\"}}",
                    spec.name,
                    spec.class,
                    if cfg!(feature = "sqlite") { "sqlite" } else { "rocksdb" },
                    spec.history_depth,
                    spec.match_stride,
                    spec.history_depth / spec.match_stride,
                    exported.artifact.index_rows.len(),
                    exported.artifact.transaction_rows.len(),
                    preparation_us,
                    g2_json_array(&export_us),
                    g2_tree_bytes(&path),
                    exported.bytes.len(),
                    exported.artifact.index_rows.iter().map(|row| row.key.len() + row.value.len()).sum::<usize>()
                        + exported.artifact.transaction_index_rows.iter().map(|row| row.key.len() + row.value.len()).sum::<usize>()
                        + exported.artifact.transaction_rows.iter().map(|row| row.key.len() + row.value.len()).sum::<usize>(),
                    exported.artifact.index_rows.len(),
                    exported.artifact.transaction_index_rows.len(),
                    exported.artifact.transaction_rows.len(),
                    exported.artifact.handoff_height,
                    g1_hex(&exported.digest.0),
                ));
            }
            "prepare" => {
                g2_prepare_destination(&path, spec);
                g2_result(&format!(
                    "{{\"mode\":\"prepare\",\"workload\":\"{}\",\"backend\":\"{}\",\"destination_bytes\":{}}}",
                    spec.name,
                    if cfg!(feature = "sqlite") { "sqlite" } else { "rocksdb" },
                    g2_tree_bytes(&path),
                ));
            }
            "import" => {
                let artifact_path = std::path::PathBuf::from(g2_required_env("D2_G2_ARTIFACT"));
                let bytes = std::fs::read(&artifact_path).expect("read G2 artifact");
                assert_eq!(
                    repeats, 1,
                    "G2 import worker measures one fresh destination"
                );
                let adapter = UpstreamAdapter::open_exclusive(&path).expect("open G2 destination");
                let d2 = crate::D2::new(adapter);
                let started = std::time::Instant::now();
                d2.inspect(&bytes).expect("G2 inspect");
                let inspection_us = started.elapsed().as_micros();
                let started = std::time::Instant::now();
                d2.validate(&bytes).expect("G2 validation");
                let validation_us = started.elapsed().as_micros();
                let started = std::time::Instant::now();
                let result = d2.import(&bytes).expect("G2 import");
                let import_us = started.elapsed().as_micros();
                drop(d2);
                let started = std::time::Instant::now();
                let reopened =
                    UpstreamAdapter::open_exclusive(&path).expect("reopen G2 destination");
                let reopened_d2 = crate::D2::new(reopened);
                reopened_d2.validate(&bytes).expect("reopen validation");
                let reopen_us = started.elapsed().as_micros();
                drop(reopened_d2);
                g2_result(&format!(
                    "{{\"mode\":\"import\",\"workload\":\"{}\",\"backend\":\"{}\",\"artifact_bytes\":{},\"inspection_us\":{},\"validation_us\":{},\"import_us\":{},\"reopen_us\":{},\"destination_bytes\":{},\"idempotent\":{},\"handoff_height\":{},\"index_rows\":{},\"transaction_index_rows\":{},\"transaction_rows\":{}}}",
                    spec.name,
                    if cfg!(feature = "sqlite") { "sqlite" } else { "rocksdb" },
                    bytes.len(),
                    inspection_us,
                    validation_us,
                    import_us,
                    reopen_us,
                    g2_tree_bytes(&path),
                    result.idempotent,
                    result.handoff_height,
                    result.index_rows,
                    result.transaction_index_rows,
                    result.transaction_rows,
                ));
            }
            "rescan" => {
                assert_eq!(
                    repeats, 1,
                    "G2 rescan worker measures one fresh destination"
                );
                let (rescan_us, script) = g2_run_rescan(&path, spec);
                g2_result(&format!(
                    "{{\"mode\":\"rescan\",\"workload\":\"{}\",\"backend\":\"{}\",\"history_depth\":{},\"rescan_us\":{},\"destination_bytes\":{},\"script_bytes\":{}}}",
                    spec.name,
                    if cfg!(feature = "sqlite") { "sqlite" } else { "rocksdb" },
                    spec.history_depth,
                    rescan_us,
                    g2_tree_bytes(&path),
                    script.as_slice().len(),
                ));
            }
            other => panic!("unknown G2 mode {other}"),
        }
    }

    /// Test-only G2 measurement worker. It deliberately exposes only timing
    /// and result data for the production D2 facade; workload construction and
    /// protocol replay remain in the pinned upstream test worker.
    #[test]
    #[ignore = "invoked by G2 realism runners"]
    fn production_g2_worker() {
        let mode = g1_required_env("D2_G2_MODE");
        let path = std::path::PathBuf::from(g1_required_env("D2_G2_STORAGE"));
        let artifact_path = std::path::PathBuf::from(g1_required_env("D2_G2_ARTIFACT"));
        let result_path = std::path::PathBuf::from(g1_required_env("D2_G2_RESULT"));
        let write_result = |value: String| {
            std::fs::write(&result_path, value).expect("write G2 D2 result");
        };

        match mode.as_str() {
            "export" => {
                let script = g1_decode_hex(&g1_required_env("D2_G2_SCRIPT"));
                let storage = Storage::new(&path);
                let d2 = crate::D2::new(UpstreamAdapter::new(storage, &path));
                let started = std::time::Instant::now();
                let exported = d2.export(&script, ScriptRole::Lock).expect("G2 D2 export");
                let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                std::fs::write(&artifact_path, &exported.bytes).expect("write G2 artifact");
                let semantic_row_bytes: usize = exported
                    .artifact
                    .index_rows
                    .iter()
                    .chain(exported.artifact.transaction_index_rows.iter())
                    .chain(exported.artifact.transaction_rows.iter())
                    .map(|row| row.key.len() + row.value.len())
                    .sum();
                write_result(format!(
                    "{{\"mode\":\"export\",\"backend\":{},\"elapsed_ms\":{},\"artifact_bytes\":{},\"semantic_row_bytes\":{},\"index_rows\":{},\"transaction_index_rows\":{},\"transaction_rows\":{},\"handoff_height\":{},\"digest\":{}}}",
                    g1_json_string(if cfg!(feature = "sqlite") { "sqlite" } else { "rocksdb" }),
                    elapsed_ms,
                    exported.bytes.len(),
                    semantic_row_bytes,
                    exported.artifact.index_rows.len(),
                    exported.artifact.transaction_index_rows.len(),
                    exported.artifact.transaction_rows.len(),
                    exported.artifact.handoff_height,
                    g1_json_string(&g1_hex(&exported.digest.0)),
                ));
            }
            "inspect" => {
                let storage = Storage::new(&path);
                let d2 = crate::D2::new(UpstreamAdapter::new(storage, &path));
                let bytes = std::fs::read(&artifact_path).expect("read G2 artifact");
                let started = std::time::Instant::now();
                let inspection = d2.inspect(&bytes).expect("G2 D2 inspect");
                let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                write_result(format!(
                    "{{\"mode\":\"inspect\",\"elapsed_ms\":{},\"artifact_bytes\":{},\"index_rows\":{},\"transaction_index_rows\":{},\"transaction_rows\":{},\"handoff_height\":{},\"digest\":{}}}",
                    elapsed_ms,
                    bytes.len(),
                    inspection.index_rows,
                    inspection.transaction_index_rows,
                    inspection.transaction_rows,
                    inspection.handoff_height,
                    g1_json_string(&g1_hex(&inspection.digest.0)),
                ));
            }
            "validate" => {
                let adapter = UpstreamAdapter::open_exclusive(&path).expect("open G2 validator");
                let d2 = crate::D2::new(adapter);
                let bytes = std::fs::read(&artifact_path).expect("read G2 artifact");
                let started = std::time::Instant::now();
                let report = d2.validate(&bytes).expect("G2 D2 validate");
                let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                write_result(format!(
                    "{{\"mode\":\"validate\",\"elapsed_ms\":{},\"idempotent\":{},\"handoff_height\":{},\"tip_height\":{}}}",
                    elapsed_ms,
                    report.idempotent,
                    report.artifact.handoff_height,
                    report.authority.tip_height,
                ));
            }
            "import" => {
                let adapter = UpstreamAdapter::open_exclusive(&path).expect("open G2 importer");
                let d2 = crate::D2::new(adapter);
                let bytes = std::fs::read(&artifact_path).expect("read G2 artifact");
                let started = std::time::Instant::now();
                let result = d2.import(&bytes).expect("G2 D2 import");
                let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                write_result(format!(
                    "{{\"mode\":\"import\",\"elapsed_ms\":{},\"idempotent\":{},\"handoff_height\":{},\"index_rows\":{},\"transaction_index_rows\":{},\"transaction_rows\":{},\"digest\":{}}}",
                    elapsed_ms,
                    result.idempotent,
                    result.handoff_height,
                    result.index_rows,
                    result.transaction_index_rows,
                    result.transaction_rows,
                    g1_json_string(&g1_hex(&result.digest.0)),
                ));
            }
            "reopen" => {
                let adapter = UpstreamAdapter::open_exclusive(&path).expect("open G2 reopener");
                let d2 = crate::D2::new(adapter);
                let bytes = std::fs::read(&artifact_path).expect("read G2 artifact");
                let started = std::time::Instant::now();
                let report = d2.validate(&bytes).expect("G2 D2 reopen validation");
                let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                write_result(format!(
                    "{{\"mode\":\"reopen\",\"elapsed_ms\":{},\"idempotent\":{},\"handoff_height\":{}}}",
                    elapsed_ms,
                    report.idempotent,
                    report.artifact.handoff_height,
                ));
            }
            other => panic!("unknown D2_G2_MODE {other}"),
        }
    }

    fn fixture_storage(path: &Path, include_script_state: bool) -> (Storage, Vec<u8>) {
        fixture_storage_at(path, include_script_state, 0)
    }

    fn fixture_storage_at(
        path: &Path,
        include_script_state: bool,
        handoff_height: u64,
    ) -> (Storage, Vec<u8>) {
        fixture_storage_at_with_seed(path, include_script_state, handoff_height, 7)
    }

    fn fixture_storage_at_with_seed(
        path: &Path,
        include_script_state: bool,
        handoff_height: u64,
        script_seed: u8,
    ) -> (Storage, Vec<u8>) {
        let storage = Storage::new(path);
        let header = packed::Header::new_builder()
            .raw(packed::RawHeader::new_builder().number(0u64).build())
            .build();
        let genesis = packed::Block::new_builder().header(header).build();
        storage.init_genesis_block(genesis);

        let script = packed::Script::new_builder()
            .code_hash(packed::Byte32::from_slice(&[script_seed; 32]).unwrap())
            .build();
        if handoff_height != 0 {
            let handoff_header = packed::Header::new_builder()
                .raw(
                    packed::RawHeader::new_builder()
                        .number(handoff_height)
                        .build(),
                )
                .build();
            let handoff_hash = handoff_header.calc_header_hash();
            let mut last_state = vec![0u8; 32];
            last_state.extend_from_slice(handoff_header.as_slice());
            let mut batch = storage.batch();
            batch.put(
                &Key::BlockHash(&handoff_hash).into_vec(),
                handoff_header.as_slice(),
            );
            batch.put(
                &Key::BlockNumber(handoff_height).into_vec(),
                handoff_hash.as_slice(),
            );
            batch.put(
                &Key::Meta(ckb_light_client_lib::storage::LAST_STATE_KEY).into_vec(),
                &last_state,
            );
            batch.commit().unwrap();
        }
        if include_script_state {
            let output = packed::CellOutput::new_builder()
                .capacity(100u64)
                .lock(script.clone())
                .build();
            let transaction = packed::Transaction::new_builder()
                .raw(
                    packed::RawTransaction::new_builder()
                        .outputs(vec![output].pack())
                        .build(),
                )
                .build();
            let tx_hash = transaction.calc_tx_hash();
            let mut batch = storage.batch();
            batch.put(
                &Key::CellLockScript(&script, handoff_height, 0, 0).into_vec(),
                tx_hash.as_slice(),
            );
            batch.put(
                &Key::TxLockScript(&script, handoff_height, 0, 0, CellType::Output).into_vec(),
                tx_hash.as_slice(),
            );
            let tx_value: Vec<u8> = Value::Transaction(handoff_height, 0, &transaction).into();
            batch.put(&Key::TxHash(&tx_hash).into_vec(), &tx_value);
            let mut registration = Key::Meta("FILTER_SCRIPTS").into_vec();
            registration.extend_from_slice(script.as_slice());
            registration.push(0);
            batch.put(&registration, &handoff_height.to_be_bytes());
            batch.put(
                &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
                &handoff_height.to_le_bytes(),
            );
            batch.commit().unwrap();
        }
        (storage, script.as_slice().to_vec())
    }

    #[test]
    fn production_adapter_round_trip_preserves_typed_state() {
        let source_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source, script) = fixture_storage(source_dir.path(), true);
        let (destination, _) = fixture_storage(destination_dir.path(), false);
        let source_adapter = UpstreamAdapter::new(source, source_dir.path());
        let destination_adapter = UpstreamAdapter::new(destination, destination_dir.path());

        let source_d2 = crate::D2::new(source_adapter.clone());
        let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();
        assert_eq!(exported.artifact.cursor, 0);
        assert_eq!(exported.artifact.index_rows.len(), 1);
        assert_eq!(exported.artifact.transaction_index_rows.len(), 1);
        assert_eq!(exported.artifact.transaction_rows.len(), 1);

        let destination_d2 = crate::D2::new(destination_adapter.clone());
        let validation = destination_d2.validate(&exported.bytes).unwrap();
        assert_eq!(validation.artifact.handoff_height, 0);
        let result = destination_d2.import(&exported.bytes).unwrap();
        assert!(!result.idempotent);
        let repeat = destination_d2.import(&exported.bytes).unwrap();
        assert!(repeat.idempotent);
    }

    #[test]
    fn production_g2_repeated_independent_script_operations_remain_coherent() {
        let source_one_dir = tempdir().unwrap();
        let source_two_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source_one, script_one) =
            fixture_storage_at_with_seed(source_one_dir.path(), true, 0, 7);
        let (source_two, script_two) =
            fixture_storage_at_with_seed(source_two_dir.path(), true, 0, 8);
        let (destination, _) = fixture_storage(destination_dir.path(), false);

        let exported_one = crate::D2::new(UpstreamAdapter::new(source_one, source_one_dir.path()))
            .export(&script_one, ScriptRole::Lock)
            .unwrap();
        let exported_two = crate::D2::new(UpstreamAdapter::new(source_two, source_two_dir.path()))
            .export(&script_two, ScriptRole::Lock)
            .unwrap();

        let destination_path = destination_dir.path().to_path_buf();
        let destination_d2 = crate::D2::new(UpstreamAdapter::new(destination, &destination_path));
        assert!(
            !destination_d2
                .import(&exported_one.bytes)
                .unwrap()
                .idempotent
        );
        assert!(
            !destination_d2
                .import(&exported_two.bytes)
                .unwrap()
                .idempotent
        );

        drop(destination_d2);
        let reopened = Storage::new(&destination_path);
        let reopened_d2 = crate::D2::new(UpstreamAdapter::new(reopened, &destination_path));
        assert!(
            reopened_d2
                .validate(&exported_one.bytes)
                .unwrap()
                .idempotent
        );
        assert!(
            reopened_d2
                .validate(&exported_two.bytes)
                .unwrap()
                .idempotent
        );

        for row in exported_rows(&exported_one.bytes)
            .into_iter()
            .chain(exported_rows(&exported_two.bytes))
        {
            assert_eq!(
                backend_get(reopened_d2.adapter().storage(), row.key).unwrap(),
                Some(row.value)
            );
        }
    }

    #[test]
    fn production_adapter_reopens_and_preserves_unrelated_state() {
        let source_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source, script) = fixture_storage(source_dir.path(), true);
        let (destination, _) = fixture_storage(destination_dir.path(), false);
        let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
        let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();

        let unrelated = packed::Script::new_builder()
            .code_hash(packed::Byte32::from_slice(&[8u8; 32]).unwrap())
            .build();
        let unrelated_key = Key::CellLockScript(&unrelated, 0, 0, 0).into_vec();
        let unrelated_value = vec![6u8; 32];
        let unrelated_registration = filter_script_key(&unrelated, ScriptRole::Lock);
        let mut destination_batch = destination.batch();
        destination_batch.put(&unrelated_key, &unrelated_value);
        destination_batch.put(&unrelated_registration, &10u64.to_be_bytes());
        destination_batch.put(
            &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
            &10u64.to_le_bytes(),
        );
        destination_batch.commit().unwrap();

        let destination_path = destination_dir.path().to_path_buf();
        {
            let destination_d2 =
                crate::D2::new(UpstreamAdapter::new(destination, &destination_path));
            let result = destination_d2.import(&exported.bytes).unwrap();
            assert!(!result.idempotent);
        }

        let reopened = Storage::new(&destination_path);
        assert_eq!(
            backend_get(&reopened, unrelated_key).unwrap(),
            Some(unrelated_value)
        );
        assert_eq!(
            backend_get(&reopened, Key::Meta("MIN_FILTERED_NUMBER").into_vec())
                .unwrap()
                .unwrap(),
            0u64.to_le_bytes()
        );
        let reopened_d2 = crate::D2::new(UpstreamAdapter::new(reopened, &destination_path));
        assert!(reopened_d2.validate(&exported.bytes).unwrap().idempotent);
    }

    #[test]
    fn production_adapter_failed_precommit_reopens_coherent_and_retries() {
        let source_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source, script) = fixture_storage(source_dir.path(), true);
        let (destination, _) = fixture_storage(destination_dir.path(), false);
        let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
        let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();
        let destination_path = destination_dir.path().to_path_buf();
        let destination_adapter = UpstreamAdapter::new(destination, &destination_path);
        destination_adapter.fail_next_commit_for_test();

        let destination_d2 = crate::D2::new(destination_adapter);
        assert!(matches!(
            destination_d2.import(&exported.bytes),
            Err(D2Error::Storage(_))
        ));
        drop(destination_d2);

        let reopened = Storage::new(&destination_path);
        assert!(
            backend_get(&reopened, exported.artifact.index_rows[0].key.clone())
                .unwrap()
                .is_none()
        );
        let reopened_d2 = crate::D2::new(UpstreamAdapter::new(reopened, &destination_path));
        assert!(!reopened_d2.validate(&exported.bytes).unwrap().idempotent);
        let retry = reopened_d2.import(&exported.bytes).unwrap();
        assert!(!retry.idempotent);
    }

    #[test]
    fn production_adapter_rejects_identity_authority_and_row_conflicts() {
        let source_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source, script) = fixture_storage(source_dir.path(), true);
        let (destination, _) = fixture_storage(destination_dir.path(), false);
        let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
        let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();

        let destination_d2 =
            crate::D2::new(UpstreamAdapter::new(destination, destination_dir.path()));

        let mut wrong_genesis = exported.artifact.clone();
        wrong_genesis.genesis_hash[0] ^= 1;
        assert!(matches!(
            destination_d2.import(&wrong_genesis.encode(&ResourceLimits::default()).unwrap()),
            Err(D2Error::ChainGenesisMismatch(_))
        ));

        let mut wrong_handoff = exported.artifact.clone();
        wrong_handoff.handoff_hash[0] ^= 1;
        assert!(matches!(
            destination_d2.import(&wrong_handoff.encode(&ResourceLimits::default()).unwrap()),
            Err(D2Error::HandoffMismatch(_))
        ));

        let mut wrong_script = exported.artifact.clone();
        wrong_script.script = packed::Script::new_builder()
            .code_hash(packed::Byte32::from_slice(&[8u8; 32]).unwrap())
            .build()
            .as_slice()
            .to_vec();
        assert!(destination_d2
            .import(&wrong_script.encode(&ResourceLimits::default()).unwrap())
            .is_err());

        let mut wrong_role = exported.artifact.clone();
        wrong_role.role = ScriptRole::Type;
        assert!(destination_d2
            .import(&wrong_role.encode(&ResourceLimits::default()).unwrap())
            .is_err());

        let conflict_dir = tempdir().unwrap();
        let (conflict_storage, _) = fixture_storage(conflict_dir.path(), false);
        let mut conflict_batch = conflict_storage.batch();
        conflict_batch.put(&exported.artifact.index_rows[0].key, &[6u8; 32]);
        conflict_batch.commit().unwrap();
        let conflict_d2 =
            crate::D2::new(UpstreamAdapter::new(conflict_storage, conflict_dir.path()));
        assert!(matches!(
            conflict_d2.import(&exported.bytes),
            Err(D2Error::DestinationConflict(_))
        ));

        let stale_dir = tempdir().unwrap();
        let (stale_storage, _) = fixture_storage(stale_dir.path(), false);
        let stale_key = filter_script_key(
            &packed::Script::from_slice(&script).unwrap(),
            ScriptRole::Lock,
        );
        let mut stale_batch = stale_storage.batch();
        stale_batch.put(&stale_key, &1u64.to_be_bytes());
        stale_batch.commit().unwrap();
        let stale_d2 = crate::D2::new(UpstreamAdapter::new(stale_storage, stale_dir.path()));
        assert!(matches!(
            stale_d2.import(&exported.bytes),
            Err(D2Error::StaleState(_))
        ));
    }

    #[test]
    fn production_export_rejects_missing_transaction_closure() {
        let source_dir = tempdir().unwrap();
        let (source, script) = fixture_storage(source_dir.path(), true);
        let cell_key =
            Key::CellLockScript(&packed::Script::from_slice(&script).unwrap(), 0, 0, 0).into_vec();
        let tx_hash = backend_get(&source, cell_key).unwrap().unwrap();
        let tx_hash = packed::Byte32::from_slice(&tx_hash).unwrap();
        let mut batch = source.batch();
        batch.delete(&Key::TxHash(&tx_hash).into_vec());
        batch.commit().unwrap();

        let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
        assert!(matches!(
            source_d2.export(&script, ScriptRole::Lock),
            Err(D2Error::ClosureFailure(_))
        ));
    }

    #[test]
    fn production_adapter_enforces_activity_and_exclusive_lifecycle() {
        let source_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source, script) = fixture_storage(source_dir.path(), true);
        let (destination, _) = fixture_storage(destination_dir.path(), false);
        let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
        let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();
        let destination_adapter = UpstreamAdapter::new(destination, destination_dir.path());
        let destination_d2 = crate::D2::new(destination_adapter.clone());

        let activity = destination_adapter.acquire_protocol_activity().unwrap();
        assert!(matches!(
            destination_d2.import(&exported.bytes),
            Err(D2Error::Lifecycle(_))
        ));
        drop(activity);

        let exclusive = destination_adapter.acquire_exclusive().unwrap();
        let contender_adapter = destination_adapter.clone();
        let contender_bytes = exported.bytes.clone();
        let contender =
            std::thread::spawn(move || crate::D2::new(contender_adapter).import(&contender_bytes));
        assert!(matches!(
            contender.join().unwrap(),
            Err(D2Error::Lifecycle(_))
        ));
        drop(exclusive);

        #[cfg(feature = "sqlite")]
        {
            let alternate_path = destination_dir.path().join("db.sqlite");
            let alternate_storage = Storage::new(&alternate_path);
            let alternate_adapter = UpstreamAdapter::new(alternate_storage, &alternate_path);
            let exclusive = destination_adapter.acquire_exclusive().unwrap();
            assert!(matches!(
                alternate_adapter.acquire_exclusive(),
                Err(D2Error::Lifecycle(_))
            ));
            drop(exclusive);
        }

        assert!(!destination_d2.import(&exported.bytes).unwrap().idempotent);
    }

    #[test]
    fn production_adapter_reorg_remains_destination_owned() {
        let source_dir = tempdir().unwrap();
        let destination_dir = tempdir().unwrap();
        let (source, script) = fixture_storage_at(source_dir.path(), true, 1);
        let (destination, _) = fixture_storage_at(destination_dir.path(), false, 1);
        let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
        let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();
        let original_hash = exported.artifact.index_rows[0].value.clone();
        let destination_adapter = UpstreamAdapter::new(destination, destination_dir.path());
        let destination_d2 = crate::D2::new(destination_adapter.clone());
        destination_d2.import(&exported.bytes).unwrap();

        let post_h_output = packed::CellOutput::new_builder()
            .capacity(102u64)
            .lock(packed::Script::from_slice(&script).unwrap())
            .build();
        let post_h_tx = packed::Transaction::new_builder()
            .raw(
                packed::RawTransaction::new_builder()
                    .outputs(vec![post_h_output].pack())
                    .build(),
            )
            .build();
        let post_h_header = packed::Header::new_builder()
            .raw(packed::RawHeader::new_builder().number(2u64).build())
            .build();
        let post_h_block = packed::Block::new_builder()
            .header(post_h_header)
            .transactions(vec![post_h_tx].pack())
            .build();
        destination_adapter.storage().filter_block(post_h_block);
        destination_adapter.storage().update_block_number(2);
        assert_eq!(
            exact_status(destination_adapter.storage(), &script, ScriptRole::Lock).unwrap(),
            Some(2)
        );

        destination_adapter.storage().rollback_to_block(1);
        assert!(backend_get(
            destination_adapter.storage(),
            exported.artifact.index_rows[0].key.clone()
        )
        .unwrap()
        .is_none());

        let replacement_output = packed::CellOutput::new_builder()
            .capacity(101u64)
            .lock(packed::Script::from_slice(&script).unwrap())
            .build();
        let replacement_tx = packed::Transaction::new_builder()
            .raw(
                packed::RawTransaction::new_builder()
                    .outputs(vec![replacement_output].pack())
                    .build(),
            )
            .build();
        let replacement_header = packed::Header::new_builder()
            .raw(packed::RawHeader::new_builder().number(1u64).build())
            .build();
        let replacement_block = packed::Block::new_builder()
            .header(replacement_header)
            .transactions(vec![replacement_tx].pack())
            .build();
        destination_adapter
            .storage()
            .filter_block(replacement_block);

        let replacement_hash = backend_get(
            destination_adapter.storage(),
            exported.artifact.index_rows[0].key.clone(),
        )
        .unwrap()
        .unwrap();
        assert_ne!(replacement_hash, original_hash);
        assert_eq!(
            exact_status(destination_adapter.storage(), &script, ScriptRole::Lock).unwrap(),
            Some(1)
        );
    }

    #[test]
    #[ignore = "requires explicit cross-backend exchange environment"]
    fn production_adapter_cross_backend_exchange() {
        let mode = std::env::var("D2_G1_EXCHANGE_MODE").expect("exchange mode");
        let artifact_path =
            std::env::var("D2_G1_EXCHANGE_ARTIFACT").expect("exchange artifact path");
        let path = PathBuf::from(artifact_path);
        if mode == "export" {
            let source_dir = tempdir().unwrap();
            let (source, script) = fixture_storage(source_dir.path(), true);
            let source_d2 = crate::D2::new(UpstreamAdapter::new(source, source_dir.path()));
            let exported = source_d2.export(&script, ScriptRole::Lock).unwrap();
            std::fs::write(path, exported.bytes).unwrap();
        } else if mode == "import" {
            let destination_dir = tempdir().unwrap();
            let (destination, script) = fixture_storage(destination_dir.path(), false);
            let destination_d2 =
                crate::D2::new(UpstreamAdapter::new(destination, destination_dir.path()));
            let bytes = std::fs::read(path).unwrap();
            let inspection = destination_d2.inspect(&bytes).unwrap();
            assert_eq!(inspection.script, script);
            let result = destination_d2.import(&bytes).unwrap();
            assert!(!result.idempotent);
            for row in exported_rows(&bytes) {
                assert_eq!(
                    backend_get(destination_d2.adapter().storage(), row.key).unwrap(),
                    Some(row.value)
                );
            }
            assert!(destination_d2.import(&bytes).unwrap().idempotent);
        } else {
            panic!("unsupported exchange mode {mode}");
        }
    }

    fn exported_rows(bytes: &[u8]) -> Vec<Row> {
        let artifact = Artifact::decode(bytes, &ResourceLimits::default())
            .unwrap()
            .0;
        artifact
            .index_rows
            .into_iter()
            .chain(artifact.transaction_index_rows)
            .chain(artifact.transaction_rows)
            .collect()
    }
}
