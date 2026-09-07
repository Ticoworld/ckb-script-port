use std::{
    collections::{BTreeSet, HashMap},
    path::{Path, PathBuf},
    sync::{Arc, Mutex, OnceLock},
};

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
}

static LIFECYCLES: OnceLock<Mutex<HashMap<PathBuf, Arc<Lifecycle>>>> = OnceLock::new();

fn lifecycle_for(path: &Path) -> Arc<Lifecycle> {
    let path = path.to_path_buf();
    let map = LIFECYCLES.get_or_init(|| Mutex::new(HashMap::new()));
    let mut map = map.lock().expect("D2 lifecycle map is not poisoned");
    Arc::clone(map.entry(path.clone()).or_insert_with(|| {
        Arc::new(Lifecycle {
            state: Mutex::new(LifecycleState::default()),
            lock_path: path.with_extension("d2.lock"),
        })
    }))
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
    file: File,
}

impl Drop for ExclusiveGuard {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

/// Adapter over the supported upstream `Storage` and `LightClientStorage`
/// traits. The type is generic so the same product code serves both native
/// backend feature builds.
pub struct UpstreamAdapter<S> {
    storage: Arc<S>,
    lifecycle: Arc<Lifecycle>,
}

impl<S> Clone for UpstreamAdapter<S> {
    fn clone(&self) -> Self {
        Self {
            storage: Arc::clone(&self.storage),
            lifecycle: Arc::clone(&self.lifecycle),
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
        let file = open_lock_file(&self.lifecycle.lock_path)?;
        file.try_lock_exclusive().map_err(|error| {
            D2Error::Lifecycle(format!("destination is not exclusively offline: {error}"))
        })?;
        Ok(ExclusiveGuard { file })
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
        validate_upstream_rows(artifact)?;
        let already_present = self.validate_destination(artifact, limits)?;
        let mut batch = self.storage.batch();
        let mut put_count = 0usize;
        for row in artifact
            .index_rows
            .iter()
            .chain(artifact.transaction_index_rows.iter())
            .chain(artifact.transaction_rows.iter())
        {
            if backend_get(self.storage.as_ref(), row.key.clone())?.is_none() {
                batch.put(&row.key, &row.value);
                put_count += 1;
            }
        }
        let script = packed::Script::from_slice(&artifact.script).map_err(|error| {
            D2Error::IdentityMismatch(format!("packed Script decode failed: {error:?}"))
        })?;
        let script_key = filter_script_key(&script, artifact.role);
        let current = exact_status(self.storage.as_ref(), &artifact.script, artifact.role)?;
        if current != Some(artifact.cursor) {
            batch.put(&script_key, &artifact.cursor.to_be_bytes());
            put_count += 1;
        }
        let min = self
            .storage
            .get_filter_scripts()
            .into_iter()
            .map(|status| {
                if status.script.as_slice() == artifact.script.as_slice()
                    && status.script_type == role_to_script_type(artifact.role)
                {
                    artifact.cursor
                } else {
                    status.block_number
                }
            })
            .min()
            .unwrap_or(artifact.cursor);
        batch.put(
            &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
            &min.to_le_bytes(),
        );
        batch
            .commit()
            .map_err(|error| D2Error::Storage(format!("native batch commit failed: {error:?}")))?;
        let _ = put_count;
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
        limit,
    );
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
    let value = backend_get(storage, Key::BlockNumber(height).into_vec())?.ok_or_else(|| {
        D2Error::HandoffMismatch(format!("destination has no block hash at height {height}"))
    })?;
    if value.len() != 32 {
        return Err(D2Error::HandoffMismatch(
            "stored block hash has invalid length".into(),
        ));
    }
    Ok(value.try_into().unwrap())
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

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use ckb_light_client_lib::storage::{BatchWriter, CellType, Storage, Value};
    use ckb_types::packed;
    use tempfile::tempdir;

    fn fixture_storage(path: &Path, include_script_state: bool) -> (Storage, Vec<u8>) {
        let storage = Storage::new(path);
        let header = packed::Header::new_builder()
            .raw(packed::RawHeader::new_builder().number(0u64).build())
            .build();
        let genesis = packed::Block::new_builder().header(header).build();
        storage.init_genesis_block(genesis);

        let script = packed::Script::new_builder()
            .code_hash(packed::Byte32::from_slice(&[7u8; 32]).unwrap())
            .build();
        if include_script_state {
            let transaction = packed::Transaction::new_builder().build();
            let tx_hash = transaction.calc_tx_hash();
            let mut batch = storage.batch();
            batch.put(
                &Key::CellLockScript(&script, 0, 0, 0).into_vec(),
                tx_hash.as_slice(),
            );
            batch.put(
                &Key::TxLockScript(&script, 0, 0, 0, CellType::Output).into_vec(),
                tx_hash.as_slice(),
            );
            let tx_value: Vec<u8> = Value::Transaction(0, 0, &transaction).into();
            batch.put(&Key::TxHash(&tx_hash).into_vec(), &tx_value);
            let mut registration = Key::Meta("FILTER_SCRIPTS").into_vec();
            registration.extend_from_slice(script.as_slice());
            registration.push(0);
            batch.put(&registration, &0u64.to_be_bytes());
            batch.put(
                &Key::Meta("MIN_FILTERED_NUMBER").into_vec(),
                &0u64.to_le_bytes(),
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
}
