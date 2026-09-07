use std::collections::BTreeSet;

use ckb_hash::blake2b_256;

use crate::{D2Error, ResourceLimits, Result};

/// The only Script namespaces supported by D2 v1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum ScriptRole {
    /// Cell lock Script namespace.
    Lock = 0,
    /// Cell type Script namespace.
    Type = 1,
}

impl TryFrom<u8> for ScriptRole {
    type Error = D2Error;

    fn try_from(value: u8) -> Result<Self> {
        match value {
            0 => Ok(Self::Lock),
            1 => Ok(Self::Type),
            other => Err(D2Error::MalformedArtifact(format!(
                "unknown Script role byte {other}"
            ))),
        }
    }
}

/// One backend-neutral upstream key/value row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    /// Canonical semantic key bytes.
    pub key: Vec<u8>,
    /// Canonical semantic value bytes.
    pub value: Vec<u8>,
}

/// The D2 v1 artifact format version.
pub const FORMAT_VERSION: u32 = 1;

const MAGIC: &[u8; 8] = b"D2SHAND1";
const DIGEST_BYTES: usize = 32;
const FIXED_HASH_BYTES: usize = 32;

/// A deterministic, backend-neutral exact-Script handoff.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Artifact {
    /// D2 artifact format version.
    pub format_version: u32,
    /// Supported upstream semantic adapter/profile identifier.
    pub adapter_profile: String,
    /// Destination chain/genesis identity.
    pub genesis_hash: [u8; FIXED_HASH_BYTES],
    /// Exact packed Script bytes.
    pub script: Vec<u8>,
    /// Script namespace.
    pub role: ScriptRole,
    /// Accepted handoff height.
    pub handoff_height: u64,
    /// Hash of the destination-recognized block at the handoff height.
    pub handoff_hash: [u8; FIXED_HASH_BYTES],
    /// Per-Script continuation cursor. V1 requires this to equal H.
    pub cursor: u64,
    /// Exact Script-derived cell/UTXO index rows.
    pub index_rows: Vec<Row>,
    /// Exact Script-derived transaction index rows.
    pub transaction_index_rows: Vec<Row>,
    /// Referenced transaction closure rows.
    pub transaction_rows: Vec<Row>,
}

/// Blake2b-256 digest of canonical artifact bytes excluding the trailing
/// digest field.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ArtifactDigest(pub [u8; DIGEST_BYTES]);

impl ArtifactDigest {
    /// Returns the raw digest bytes.
    pub fn as_bytes(&self) -> &[u8; DIGEST_BYTES] {
        &self.0
    }
}

/// Non-mutating artifact inspection result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtifactInspection {
    /// Format version.
    pub format_version: u32,
    /// Adapter/profile identifier.
    pub adapter_profile: String,
    /// Exact Script bytes.
    pub script: Vec<u8>,
    /// Script role.
    pub role: ScriptRole,
    /// Genesis hash.
    pub genesis_hash: [u8; FIXED_HASH_BYTES],
    /// Handoff height.
    pub handoff_height: u64,
    /// Handoff block hash.
    pub handoff_hash: [u8; FIXED_HASH_BYTES],
    /// Continuation cursor.
    pub cursor: u64,
    /// Number of index rows.
    pub index_rows: usize,
    /// Number of transaction-index rows.
    pub transaction_index_rows: usize,
    /// Number of transaction closure rows.
    pub transaction_rows: usize,
    /// Artifact digest.
    pub digest: ArtifactDigest,
}

impl Artifact {
    /// Computes the digest over canonical bytes.
    pub fn digest(&self, limits: &ResourceLimits) -> Result<ArtifactDigest> {
        let bytes = self.encode_without_digest(limits)?;
        Ok(ArtifactDigest(blake2b_256(bytes)))
    }

    /// Encodes the artifact with its trailing integrity digest.
    pub fn encode(&self, limits: &ResourceLimits) -> Result<Vec<u8>> {
        let mut bytes = self.encode_without_digest(limits)?;
        let digest = blake2b_256(&bytes);
        bytes.extend_from_slice(&digest);
        if bytes.len() > limits.max_artifact_bytes {
            return Err(D2Error::ResourceLimit(format!(
                "artifact is {} bytes, limit is {}",
                bytes.len(),
                limits.max_artifact_bytes
            )));
        }
        Ok(bytes)
    }

    /// Decodes and validates a complete artifact.
    pub fn decode(bytes: &[u8], limits: &ResourceLimits) -> Result<(Self, ArtifactDigest)> {
        if bytes.len() > limits.max_artifact_bytes {
            return Err(D2Error::ResourceLimit(format!(
                "artifact is {} bytes, limit is {}",
                bytes.len(),
                limits.max_artifact_bytes
            )));
        }
        if bytes.len() < MAGIC.len() + 4 + DIGEST_BYTES {
            return Err(D2Error::MalformedArtifact("artifact is truncated".into()));
        }

        let digest_offset = bytes.len() - DIGEST_BYTES;
        let expected = blake2b_256(&bytes[..digest_offset]);
        if bytes[digest_offset..] != expected {
            return Err(D2Error::MalformedArtifact(
                "artifact digest mismatch".into(),
            ));
        }

        let mut reader = Reader::new(&bytes[..digest_offset], limits);
        let magic = reader.read_exact(MAGIC.len())?;
        if magic != MAGIC {
            return Err(D2Error::MalformedArtifact("wrong artifact magic".into()));
        }
        let format_version = reader.read_u32()?;
        if format_version != FORMAT_VERSION {
            return Err(D2Error::UnsupportedFormat(format_version));
        }
        let adapter_profile = reader.read_string(limits.max_profile_bytes)?;
        let genesis_hash = reader.read_hash()?;
        let script = reader.read_bytes(limits.max_script_bytes)?;
        let role = ScriptRole::try_from(reader.read_u8()?)?;
        let handoff_height = reader.read_u64()?;
        let handoff_hash = reader.read_hash()?;
        let cursor = reader.read_u64()?;
        let index_rows = reader.read_rows(limits.max_rows_per_section, limits.max_record_bytes)?;
        let transaction_index_rows =
            reader.read_rows(limits.max_rows_per_section, limits.max_record_bytes)?;
        let transaction_rows =
            reader.read_rows(limits.max_transaction_rows, limits.max_record_bytes)?;
        reader.finish()?;

        let artifact = Self {
            format_version,
            adapter_profile,
            genesis_hash,
            script,
            role,
            handoff_height,
            handoff_hash,
            cursor,
            index_rows,
            transaction_index_rows,
            transaction_rows,
        };
        artifact.validate(limits)?;
        Ok((artifact, ArtifactDigest(expected)))
    }

    /// Returns a compact, non-mutating summary of a decoded artifact.
    pub fn inspect(bytes: &[u8], limits: &ResourceLimits) -> Result<ArtifactInspection> {
        let (artifact, digest) = Self::decode(bytes, limits)?;
        Ok(ArtifactInspection {
            format_version: artifact.format_version,
            adapter_profile: artifact.adapter_profile,
            script: artifact.script,
            role: artifact.role,
            genesis_hash: artifact.genesis_hash,
            handoff_height: artifact.handoff_height,
            handoff_hash: artifact.handoff_hash,
            cursor: artifact.cursor,
            index_rows: artifact.index_rows.len(),
            transaction_index_rows: artifact.transaction_index_rows.len(),
            transaction_rows: artifact.transaction_rows.len(),
            digest,
        })
    }

    /// Validates the canonical model and its closure relationship.
    pub fn validate(&self, limits: &ResourceLimits) -> Result<()> {
        if self.format_version != FORMAT_VERSION {
            return Err(D2Error::UnsupportedFormat(self.format_version));
        }
        if self.adapter_profile.is_empty() {
            return Err(D2Error::UnsupportedProfile("empty adapter profile".into()));
        }
        if self.adapter_profile.len() > limits.max_profile_bytes {
            return Err(D2Error::ResourceLimit(
                "adapter profile is too large".into(),
            ));
        }
        if self.script.is_empty() || self.script.len() > limits.max_script_bytes {
            return Err(D2Error::IdentityMismatch(
                "packed Script has invalid length".into(),
            ));
        }
        if self.cursor != self.handoff_height {
            return Err(D2Error::HandoffMismatch(
                "v1 requires cursor to equal handoff height".into(),
            ));
        }
        validate_rows(
            "index",
            &self.index_rows,
            limits.max_rows_per_section,
            limits.max_record_bytes,
        )?;
        validate_rows(
            "transaction-index",
            &self.transaction_index_rows,
            limits.max_rows_per_section,
            limits.max_record_bytes,
        )?;
        validate_rows(
            "transaction",
            &self.transaction_rows,
            limits.max_transaction_rows,
            limits.max_record_bytes,
        )?;

        let referenced = self
            .index_rows
            .iter()
            .chain(self.transaction_index_rows.iter())
            .map(|row| {
                if row.value.len() != 32 {
                    return Err(D2Error::ClosureFailure(
                        "Script index row value is not a 32-byte transaction hash".into(),
                    ));
                }
                let mut hash = [0u8; 32];
                hash.copy_from_slice(&row.value);
                Ok(hash)
            })
            .collect::<Result<BTreeSet<_>>>()?;

        let closure = self
            .transaction_rows
            .iter()
            .map(|row| {
                if row.key.len() != 33 || row.key[0] != 0 || row.value.len() < 12 {
                    return Err(D2Error::ClosureFailure(
                        "transaction closure row has invalid key/value shape".into(),
                    ));
                }
                let mut hash = [0u8; 32];
                hash.copy_from_slice(&row.key[1..]);
                Ok(hash)
            })
            .collect::<Result<BTreeSet<_>>>()?;

        if referenced != closure {
            return Err(D2Error::ClosureFailure(
                "transaction closure does not exactly match Script index references".into(),
            ));
        }
        Ok(())
    }

    fn encode_without_digest(&self, limits: &ResourceLimits) -> Result<Vec<u8>> {
        self.validate(limits)?;
        let mut output = Vec::new();
        output.extend_from_slice(MAGIC);
        output.extend_from_slice(&self.format_version.to_le_bytes());
        write_string(&mut output, &self.adapter_profile, limits.max_profile_bytes)?;
        output.extend_from_slice(&self.genesis_hash);
        write_bytes(&mut output, &self.script, limits.max_script_bytes)?;
        output.push(self.role as u8);
        output.extend_from_slice(&self.handoff_height.to_le_bytes());
        output.extend_from_slice(&self.handoff_hash);
        output.extend_from_slice(&self.cursor.to_le_bytes());
        write_rows(
            &mut output,
            &self.index_rows,
            limits.max_rows_per_section,
            limits.max_record_bytes,
        )?;
        write_rows(
            &mut output,
            &self.transaction_index_rows,
            limits.max_rows_per_section,
            limits.max_record_bytes,
        )?;
        write_rows(
            &mut output,
            &self.transaction_rows,
            limits.max_transaction_rows,
            limits.max_record_bytes,
        )?;
        if output.len() + DIGEST_BYTES > limits.max_artifact_bytes {
            return Err(D2Error::ResourceLimit("artifact exceeds byte limit".into()));
        }
        Ok(output)
    }
}

fn validate_rows(
    section: &str,
    rows: &[Row],
    max_rows: usize,
    max_record_bytes: usize,
) -> Result<()> {
    if rows.len() > max_rows {
        return Err(D2Error::ResourceLimit(format!(
            "{section} row count {} exceeds {max_rows}",
            rows.len()
        )));
    }
    let mut previous: Option<&[u8]> = None;
    for row in rows {
        if row.key.is_empty() || row.value.is_empty() {
            return Err(D2Error::MalformedArtifact(format!(
                "{section} row has an empty key or value"
            )));
        }
        if row.key.len() > max_record_bytes || row.value.len() > max_record_bytes {
            return Err(D2Error::ResourceLimit(format!(
                "{section} row exceeds record limit"
            )));
        }
        if let Some(previous) = previous {
            if previous >= row.key.as_slice() {
                return Err(D2Error::MalformedArtifact(format!(
                    "{section} rows are not strictly canonical"
                )));
            }
        }
        previous = Some(&row.key);
    }
    Ok(())
}

fn write_string(output: &mut Vec<u8>, value: &str, limit: usize) -> Result<()> {
    write_bytes(output, value.as_bytes(), limit)
}

fn write_bytes(output: &mut Vec<u8>, value: &[u8], limit: usize) -> Result<()> {
    if value.len() > limit || value.len() > u32::MAX as usize {
        return Err(D2Error::ResourceLimit("encoded field exceeds limit".into()));
    }
    output.extend_from_slice(&(value.len() as u32).to_le_bytes());
    output.extend_from_slice(value);
    Ok(())
}

fn write_rows(
    output: &mut Vec<u8>,
    rows: &[Row],
    max_rows: usize,
    max_record_bytes: usize,
) -> Result<()> {
    validate_rows("row", rows, max_rows, max_record_bytes)?;
    if rows.len() > u32::MAX as usize {
        return Err(D2Error::ResourceLimit("too many rows".into()));
    }
    output.extend_from_slice(&(rows.len() as u32).to_le_bytes());
    for row in rows {
        write_bytes(output, &row.key, max_record_bytes)?;
        write_bytes(output, &row.value, max_record_bytes)?;
    }
    Ok(())
}

struct Reader<'a> {
    input: &'a [u8],
    offset: usize,
    limits: &'a ResourceLimits,
}

impl<'a> Reader<'a> {
    fn new(input: &'a [u8], limits: &'a ResourceLimits) -> Self {
        Self {
            input,
            offset: 0,
            limits,
        }
    }

    fn read_exact(&mut self, length: usize) -> Result<&'a [u8]> {
        let end = self
            .offset
            .checked_add(length)
            .ok_or_else(|| D2Error::MalformedArtifact("reader offset overflow".into()))?;
        if end > self.input.len() {
            return Err(D2Error::MalformedArtifact("artifact is truncated".into()));
        }
        let value = &self.input[self.offset..end];
        self.offset = end;
        Ok(value)
    }

    fn read_u8(&mut self) -> Result<u8> {
        Ok(self.read_exact(1)?[0])
    }

    fn read_u32(&mut self) -> Result<u32> {
        Ok(u32::from_le_bytes(self.read_exact(4)?.try_into().unwrap()))
    }

    fn read_u64(&mut self) -> Result<u64> {
        Ok(u64::from_le_bytes(self.read_exact(8)?.try_into().unwrap()))
    }

    fn read_hash(&mut self) -> Result<[u8; 32]> {
        Ok(self.read_exact(32)?.try_into().unwrap())
    }

    fn read_bytes(&mut self, limit: usize) -> Result<Vec<u8>> {
        let length = self.read_u32()? as usize;
        if length > limit {
            return Err(D2Error::ResourceLimit(format!(
                "declared field length {length} exceeds {limit}"
            )));
        }
        Ok(self.read_exact(length)?.to_vec())
    }

    fn read_string(&mut self, limit: usize) -> Result<String> {
        let bytes = self.read_bytes(limit)?;
        String::from_utf8(bytes)
            .map_err(|_| D2Error::MalformedArtifact("adapter profile is not UTF-8".into()))
    }

    fn read_rows(&mut self, max_rows: usize, max_record_bytes: usize) -> Result<Vec<Row>> {
        let count = self.read_u32()? as usize;
        if count > max_rows {
            return Err(D2Error::ResourceLimit(format!(
                "declared row count {count} exceeds {max_rows}"
            )));
        }
        let mut rows = Vec::with_capacity(count);
        for _ in 0..count {
            rows.push(Row {
                key: self.read_bytes(max_record_bytes)?,
                value: self.read_bytes(max_record_bytes)?,
            });
        }
        Ok(rows)
    }

    fn finish(&self) -> Result<()> {
        if self.offset != self.input.len() {
            return Err(D2Error::MalformedArtifact("trailing artifact bytes".into()));
        }
        let _ = self.limits;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Artifact {
        let hash = [7u8; 32];
        Artifact {
            format_version: FORMAT_VERSION,
            adapter_profile: "test-profile".into(),
            genesis_hash: hash,
            script: vec![1, 2, 3],
            role: ScriptRole::Lock,
            handoff_height: 9,
            handoff_hash: [8u8; 32],
            cursor: 9,
            index_rows: vec![Row {
                key: vec![1],
                value: hash.to_vec(),
            }],
            transaction_index_rows: vec![Row {
                key: vec![2],
                value: hash.to_vec(),
            }],
            transaction_rows: vec![Row {
                key: [0].into_iter().chain(hash).collect(),
                value: vec![0; 12],
            }],
        }
    }

    #[test]
    fn deterministic_round_trip() {
        let limits = ResourceLimits::default();
        let artifact = sample();
        let first = artifact.encode(&limits).unwrap();
        let second = artifact.encode(&limits).unwrap();
        assert_eq!(first, second);
        let (decoded, digest) = Artifact::decode(&first, &limits).unwrap();
        assert_eq!(decoded, artifact);
        assert_eq!(digest, artifact.digest(&limits).unwrap());
    }

    #[test]
    fn rejects_wrong_magic_and_digest() {
        let limits = ResourceLimits::default();
        let bytes = sample().encode(&limits).unwrap();
        let mut wrong_magic = bytes.clone();
        wrong_magic[0] ^= 1;
        assert!(matches!(
            Artifact::decode(&wrong_magic, &limits),
            Err(D2Error::MalformedArtifact(_))
        ));
        let mut wrong_digest = bytes;
        let last = wrong_digest.len() - 1;
        wrong_digest[last] ^= 1;
        assert!(matches!(
            Artifact::decode(&wrong_digest, &limits),
            Err(D2Error::MalformedArtifact(_))
        ));
    }

    #[test]
    fn rejects_noncanonical_rows_and_unknown_version() {
        let limits = ResourceLimits::default();
        let mut artifact = sample();
        artifact.index_rows = vec![
            Row {
                key: vec![2],
                value: [7u8; 32].to_vec(),
            },
            Row {
                key: vec![1],
                value: [7u8; 32].to_vec(),
            },
        ];
        assert!(matches!(
            artifact.encode(&limits),
            Err(D2Error::MalformedArtifact(_))
        ));
        let mut artifact = sample();
        artifact.format_version = 99;
        assert!(matches!(
            artifact.encode(&limits),
            Err(D2Error::UnsupportedFormat(99))
        ));
    }

    #[test]
    fn rejects_missing_and_unexpected_closure() {
        let limits = ResourceLimits::default();
        let mut artifact = sample();
        artifact.transaction_rows.clear();
        assert!(matches!(
            artifact.validate(&limits),
            Err(D2Error::ClosureFailure(_))
        ));
        let mut artifact = sample();
        artifact.transaction_rows.push(Row {
            key: std::iter::once(0)
                .chain(std::iter::repeat_n(9, 32))
                .collect(),
            value: vec![0; 12],
        });
        assert!(matches!(
            artifact.validate(&limits),
            Err(D2Error::MalformedArtifact(_)) | Err(D2Error::ClosureFailure(_))
        ));
    }
}
