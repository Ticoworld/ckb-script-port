/// Bounded parser/import resource limits.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ResourceLimits {
    /// Maximum complete artifact size, including its digest.
    pub max_artifact_bytes: usize,
    /// Maximum packed Script byte length.
    pub max_script_bytes: usize,
    /// Maximum adapter/profile byte length.
    pub max_profile_bytes: usize,
    /// Maximum number of rows across each row section.
    pub max_rows_per_section: usize,
    /// Maximum number of transaction closure rows.
    pub max_transaction_rows: usize,
    /// Maximum key or value byte length for one row.
    pub max_record_bytes: usize,
}

impl Default for ResourceLimits {
    fn default() -> Self {
        Self {
            max_artifact_bytes: 64 * 1024 * 1024,
            max_script_bytes: 64 * 1024,
            max_profile_bytes: 256,
            max_rows_per_section: 1_000_000,
            max_transaction_rows: 100_000,
            max_record_bytes: 4 * 1024 * 1024,
        }
    }
}
