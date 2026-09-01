$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'
$RunRoot = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2d'
$Events = Join-Path $RunRoot 'events'
$Results = Join-Path $RunRoot 'results'
$Logs = Join-Path $RunRoot 'process-logs'
$CrashRoot = Join-Path $RunRoot 'crash-matrix'
$Verifier = Join-Path $PSScriptRoot '..\src\rp2a_verifier.py'
$Comparator = Join-Path $PSScriptRoot '..\src\compare_rp2d.py'
$ConsistencyVerifier = Join-Path $PSScriptRoot '..\src\rp2d_consistency_verifier.py'

if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw 'Unexpected pinned upstream HEAD before RP2-D' }

# Reproduce the accepted measuring instruments before adding the D-only patch.
& (Join-Path $PSScriptRoot 'run-rp2c.ps1')
if ($LASTEXITCODE -ne 0) { throw 'RP2-A/B/C reproduction failed; RP2-D is blocked' }
& (Join-Path $PSScriptRoot 'apply-rp2d-upstream-patches.ps1')

if (Test-Path -LiteralPath $RunRoot) {
    $resolvedRun = (Resolve-Path -LiteralPath $RunRoot).Path
    $resolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not $resolvedRun.StartsWith($resolvedProject, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to reset outside project: $resolvedRun" }
    [System.IO.Directory]::Delete($resolvedRun, $true)
}
New-Item -ItemType Directory -Force -Path $Events, $Results, $Logs, $CrashRoot | Out-Null

$env:RUSTUP_TOOLCHAIN = 'stable'
$env:CARGO_BUILD_JOBS = '1'
$env:CXXFLAGS = '-D_WIN32_WINNT=0x0602'
$BundledLibclang = Join-Path $ProjectRoot '_work\libclang\package\runtimes\win-x64\native'
if (Test-Path -LiteralPath (Join-Path $BundledLibclang 'libclang.dll')) { $env:LIBCLANG_PATH = $BundledLibclang }
else { throw 'The disposable libclang prerequisite is missing' }

$RocksTarget = Join-Path $ProjectRoot '_work\build\rocksdb'
$SqliteTarget = Join-Path $ProjectRoot '_work\build\sqlite'
Push-Location -LiteralPath $Upstream
try {
    function Build-Worker([string]$backend, [string]$target) {
        $env:CARGO_TARGET_DIR = $target
        if ($backend -eq 'sqlite') {
            & cargo test --manifest-path light-client-lib/Cargo.toml --no-default-features --features sqlite rp2d_reorg_worker --no-run --locked
        } else {
            & cargo test --manifest-path light-client-lib/Cargo.toml rp2d_reorg_worker --no-run --locked
        }
        if ($LASTEXITCODE -ne 0) { throw "RP2-D build failed for $backend" }
    }
    Build-Worker 'rocksdb' $RocksTarget
    Build-Worker 'sqlite' $SqliteTarget

    function Worker-Args([string]$backend, [string]$target) {
        if ($backend -eq 'sqlite') {
            return @('test','--manifest-path','light-client-lib/Cargo.toml','--no-default-features','--features','sqlite','rp2d_reorg_worker','--','--test-threads=1','--nocapture')
        }
        return @('test','--manifest-path','light-client-lib/Cargo.toml','rp2d_reorg_worker','--','--test-threads=1','--nocapture')
    }
    function Invoke-Worker {
        param([string]$backend,[string]$target,[string]$mode,[string]$case,[string]$output,[string]$artifact,[string]$processId,[string]$dbPath,[string]$expectedState)
        $env:CARGO_TARGET_DIR = $target
        $env:RP2_RUN_ROOT = $RunRoot
        $env:RP2_EVENT_DIR = $Events
        $env:RP2C_MODE = ''
        $env:RP2C_CASE = $case
        $env:RP2C_OUTPUT = $output
        $env:RP2C_PROCESS_ID = $processId
        $env:RP2D_MODE = $mode
        if ($artifact) { $env:RP2C_ARTIFACT = $artifact } else { Remove-Item Env:RP2C_ARTIFACT -ErrorAction SilentlyContinue }
        if ($dbPath) { $env:RP2D_DB_PATH = $dbPath } else { Remove-Item Env:RP2D_DB_PATH -ErrorAction SilentlyContinue }
        if ($expectedState) { $env:RP2D_EXPECTED_STATE = $expectedState } else { Remove-Item Env:RP2D_EXPECTED_STATE -ErrorAction SilentlyContinue }
        $args = Worker-Args $backend $target
        $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $lines = @(& cargo @args 2>&1 | ForEach-Object { $_.ToString() })
        $ErrorActionPreference = $saved
        $exit = $LASTEXITCODE
        $log = Join-Path $Logs ($processId + '.log')
        $lines | Set-Content -LiteralPath $log -Encoding utf8
        if ($exit -ne 0) { throw "RP2-D worker failed: $processId ($backend/$mode), exit $exit. See $log" }
        if (-not (Test-Path -LiteralPath $output)) { throw "Worker did not write $output" }
        return [ordered]@{ process_id=$processId; backend=$backend; mode=$mode; case=$case; output=$output; log=$log; exit_code=$exit }
    }

    $directions = @(
        [ordered]@{ name='c1-rocksdb-to-sqlite'; source='rocksdb'; destination='sqlite'; destTarget=$SqliteTarget },
        [ordered]@{ name='c2-sqlite-to-rocksdb'; source='sqlite'; destination='rocksdb'; destTarget=$RocksTarget },
        # Same-backend controls are diagnostic: the cross-backend directions
        # remain the D2 portability claim, but these controls isolate backend
        # rollback behavior from transport translation.
        [ordered]@{ name='s1-rocksdb-to-rocksdb'; source='rocksdb'; destination='rocksdb'; destTarget=$RocksTarget },
        [ordered]@{ name='s2-sqlite-to-sqlite'; source='sqlite'; destination='sqlite'; destTarget=$SqliteTarget }
    )
    $processes = @()
    $losingEvidence = @()
    foreach ($d in $directions) {
        $artifactName = if ($d.name -eq 's1-rocksdb-to-rocksdb') { 'c1-rocksdb-to-sqlite-source' } elseif ($d.name -eq 's2-sqlite-to-sqlite') { 'c2-sqlite-to-rocksdb-source' } else { $d.name + '-source' }
        $artifact = Join-Path (Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2c\artifacts') ($artifactName + '\valid.json')
        if (-not (Test-Path -LiteralPath $artifact)) { throw "Accepted source artifact missing: $artifact" }
        $baseOut = Join-Path $Results ($d.name + '-baseline.json')
        $impOut = Join-Path $Results ($d.name + '-import.json')
        $processes += Invoke-Worker $d.destination $d.destTarget 'baseline' ($d.name + '-baseline') $baseOut '' ($d.name + '-baseline-' + $d.destination) '' ''
        $processes += Invoke-Worker $d.destination $d.destTarget 'import' ($d.name + '-import') $impOut $artifact ($d.name + '-import-' + $d.destination) '' ''
        if ($d.name -in @('c1-rocksdb-to-sqlite','c2-sqlite-to-rocksdb')) {
            $losingOut = Join-Path $Results ($d.name + '-losing-artifact.json')
            $processes += Invoke-Worker $d.destination $d.destTarget 'losing-artifact' ($d.name + '-losing-artifact') $losingOut $artifact ($d.name + '-losing-' + $d.destination) '' ''
            $losingEvidence += (Get-Content $losingOut -Raw | ConvertFrom-Json)
        }
        $cmp = Join-Path $Results ($d.name + '-comparison.json')
        & python $Comparator --case $d.name --baseline $baseOut --import $impOut --output $cmp
        if ($LASTEXITCODE -ne 0) { throw "RP2-D reorg comparison failed: $($d.name)" }
    }

    # The deeper-fork case is deliberately diagnostic.  It crosses the
    # upstream retained-header boundary and therefore must not be turned into
    # a synthetic success by direct storage rollback.
    $deepEvidence = @()
    foreach ($backend in @('rocksdb','sqlite')) {
        $target = if ($backend -eq 'rocksdb') { $RocksTarget } else { $SqliteTarget }
        $deepOut = Join-Path $Results ($backend + '-deep-fork.json')
        $deepEvidence += Invoke-Worker $backend $target 'deep' ($backend + '-deep-fork') $deepOut '' ($backend + '-deep-fork') '' ''
    }

    # A direct executable is used for abort/reopen so the parent can observe a
    # genuine process death rather than a caught Rust panic.
    function Find-TestExe([string]$target) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $target 'debug\deps') -File |
            Where-Object { $_.Name -match '^ckb_light_client_lib-[0-9a-f]+\.exe$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $candidate) { throw "Test executable not found in $target" }
        return $candidate.FullName
    }
    $stages = 0..9 | ForEach-Object { 'C' + $_ }
    $crashRecords = @()
    foreach ($backend in @('rocksdb','sqlite')) {
        $target = if ($backend -eq 'rocksdb') { $RocksTarget } else { $SqliteTarget }
        $exe = Find-TestExe $target
        $artifactName = if ($backend -eq 'rocksdb') { 'c2-sqlite-to-rocksdb-source' } else { 'c1-rocksdb-to-sqlite-source' }
        $artifact = Join-Path (Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2c\artifacts') ($artifactName + '\valid.json')
        foreach ($stage in $stages) {
            $stageRoot = Join-Path (Join-Path $CrashRoot $backend) $stage
            $db = Join-Path $stageRoot 'db'; $crashOut = Join-Path $stageRoot 'crash.json'; $reopenOut = Join-Path $stageRoot 'reopen.json'; $retryOut = Join-Path $stageRoot 'retry.json'; $authorityBeforePath = Join-Path $stageRoot 'authority-before.json'
            New-Item -ItemType Directory -Force -Path $db | Out-Null
            $common = @('--exact','tests::rp2_authority_replay::rp2d_reorg_worker','--nocapture')
            $env:CARGO_TARGET_DIR = $target; $env:RP2_RUN_ROOT=$RunRoot; $env:RP2_EVENT_DIR=$Events; $env:RP2D_MODE='crash-import'; $env:RP2D_CRASH_STAGE=$stage; $env:RP2D_DB_PATH=$db; $env:RP2D_AUTHORITY_BEFORE=$authorityBeforePath; $env:RP2C_ARTIFACT=$artifact; $env:RP2C_OUTPUT=$crashOut; $env:RP2C_PROCESS_ID=($backend + '-' + $stage + '-crash'); $env:RP2C_CASE=($backend + '-' + $stage)
            $saved = $ErrorActionPreference; $ErrorActionPreference='Continue'; $lines=@(& $exe @common 2>&1 | ForEach-Object { $_.ToString() }); $ErrorActionPreference=$saved; $exit=$LASTEXITCODE
            $lines | Set-Content -LiteralPath (Join-Path $Logs ($backend + '-' + $stage + '-crash.log')) -Encoding utf8
            if ($exit -eq 0) { throw "Crash failpoint $backend/$stage unexpectedly completed" }
            Remove-Item Env:RP2D_CRASH_STAGE -ErrorAction SilentlyContinue
            $expected = if ($stage -in @('C0','C1','C2','C3','C4','C5','C6','C7')) { 'OLD_COMPLETE' } else { 'NEW_COMPLETE' }
            $env:RP2D_MODE='reopen'; $env:RP2D_EXPECTED_STATE=$expected; $env:RP2C_OUTPUT=$reopenOut; $env:RP2C_PROCESS_ID=($backend + '-' + $stage + '-reopen')
            $saved = $ErrorActionPreference; $ErrorActionPreference='Continue'; $reopenLines=@(& $exe @common 2>&1 | ForEach-Object { $_.ToString() }); $ErrorActionPreference=$saved; $reopenExit=$LASTEXITCODE
            $reopenLines | Set-Content -LiteralPath (Join-Path $Logs ($backend + '-' + $stage + '-reopen.log')) -Encoding utf8
            if ($reopenExit -ne 0) { throw "Crash reopen failed for $backend/$stage; see logs" }
            if (-not (Test-Path -LiteralPath $authorityBeforePath)) { throw "Crash worker did not write authority-before fingerprint for $backend/$stage" }
            # Retry the exact typed import after reopening. This exercises the
            # idempotent recovery path without changing authority.
            $env:RP2D_MODE='crash-import'; $env:RP2C_OUTPUT=$retryOut; $env:RP2C_PROCESS_ID=($backend + '-' + $stage + '-retry'); Remove-Item Env:RP2D_EXPECTED_STATE -ErrorAction SilentlyContinue
            $saved = $ErrorActionPreference; $ErrorActionPreference='Continue'; $retryLines=@(& $exe @common 2>&1 | ForEach-Object { $_.ToString() }); $ErrorActionPreference=$saved; $retryExit=$LASTEXITCODE
            $retryLines | Set-Content -LiteralPath (Join-Path $Logs ($backend + '-' + $stage + '-retry.log')) -Encoding utf8
            if ($retryExit -ne 0 -or -not (Test-Path -LiteralPath $retryOut)) { throw "Retry after crash failed for $backend/$stage" }
            $sourceArtifactBackend = if ($backend -eq 'rocksdb') { 'sqlite' } else { 'rocksdb' }
            $crashRecords += [ordered]@{ backend=$backend; source_artifact_backend=$sourceArtifactBackend; stage=$stage; crash_exit_code=$exit; reopen_exit_code=$reopenExit; retry_exit_code=$retryExit; expected=$expected; authority_before=(Get-Content $authorityBeforePath -Raw | ConvertFrom-Json); reopen=(Get-Content $reopenOut -Raw | ConvertFrom-Json); retry=(Get-Content $retryOut -Raw | ConvertFrom-Json) }
        }
    }
    $processes | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $Results 'processes.json') -Encoding utf8
    $losingEvidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $Results 'losing-artifact.json') -Encoding utf8
    $crashRecords | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Results 'crash-matrix.json') -Encoding utf8
} finally { Pop-Location }

& python $Verifier --events-dir $Events --output (Join-Path $Results 'rp2d-verification.json')
if ($LASTEXITCODE -ne 0) { throw 'Independent RP2-A verifier rejected RP2-D event evidence' }
& python $ConsistencyVerifier --crash-matrix (Join-Path $Results 'crash-matrix.json') --output (Join-Path $Results 'rp2d-consistency-verification.json')
if ($LASTEXITCODE -ne 0) { throw 'Independent RP2-D persisted-state consistency verifier rejected crash evidence' }

$comparisons = @{}
foreach ($name in @('c1-rocksdb-to-sqlite','c2-sqlite-to-rocksdb')) { $comparisons[$name] = Get-Content (Join-Path $Results ($name + '-comparison.json')) -Raw | ConvertFrom-Json }
$verification = Get-Content (Join-Path $Results 'rp2d-verification.json') -Raw | ConvertFrom-Json
$consistency = Get-Content (Join-Path $Results 'rp2d-consistency-verification.json') -Raw | ConvertFrom-Json
$crash = Get-Content (Join-Path $Results 'crash-matrix.json') -Raw | ConvertFrom-Json
$allComparisonPass = $true; foreach ($v in $comparisons.Values) { if (-not $v.passed) { $allComparisonPass = $false } }
$allCrashPass = @($crash).Count -eq 20 -and (@($crash | Where-Object { $_.reopen.consistency -ne $_.expected -or $_.crash_exit_code -eq 0 -or $_.retry_exit_code -ne 0 }).Count -eq 0)
$losingPass = @($losingEvidence).Count -eq 2 -and (@($losingEvidence | Where-Object { -not $_.rejected -or -not $_.authority_unchanged }).Count -eq 0)
$deep = @()
foreach ($backend in @('rocksdb','sqlite')) {
    $deep += Get-Content (Join-Path $Results ($backend + '-deep-fork.json')) -Raw | ConvertFrom-Json
}
$patch5 = Join-Path $ProjectRoot 'patches\rp2\0005-rp2d-reorg-crash-test.patch'
$artifact_remove_after_validation_tested = $false
$offline_exclusive_enforced = $false
$simultaneous_imports_tested = $false
$commit_inside_engine_exercised = $false
$coreMatrixPass = $allComparisonPass -and $verification.passed -and $allCrashPass -and $losingPass
$verdict = if ($coreMatrixPass -and $artifact_remove_after_validation_tested -and $offline_exclusive_enforced -and $simultaneous_imports_tested -and $commit_inside_engine_exercised) { [string]::Concat('RP2-D PASS ',[char]0x2014,' PROCEED TO PDEF1 SCOPE FREEZE') } elseif ($coreMatrixPass) { [string]::Concat('RP2-D CONDITIONAL PASS ',[char]0x2014,' SMALL SAFETY SEAM REQUIRED BEFORE PDEF1') } else { [string]::Concat('RP2-D PARTIAL ',[char]0x2014,' CRASH SAFETY REPAIR REQUIRED') }
$summary = [ordered]@{
    schema_version=1; experiment='D2-RP2D-reorg-crash-correctness'; captured_utc=(Get-Date).ToUniversalTime().ToString('o'); project_commit=(git -C $ProjectRoot rev-parse HEAD).Trim(); upstream_revision=$Pinned
    handoff_seam_changed=$false; patches=[ordered]@{ '0002-rp2b-typed-script-handoff.patch'=(Get-FileHash (Join-Path $ProjectRoot 'patches\rp2\0002-rp2b-typed-script-handoff.patch') -Algorithm SHA256).Hash; '0003-rp2b-spendable-fixture.patch'=(Get-FileHash (Join-Path $ProjectRoot 'patches\rp2\0003-rp2b-spendable-fixture.patch') -Algorithm SHA256).Hash; '0004-rp2c-cross-backend-transport.patch'=(Get-FileHash (Join-Path $ProjectRoot 'patches\rp2\0004-rp2c-cross-backend-transport.patch') -Algorithm SHA256).Hash; '0005-rp2d-reorg-crash-test.patch'=(Get-FileHash $patch5 -Algorithm SHA256).Hash }
    comparisons=$comparisons; verifier=$verification; consistency_verifier=$consistency; crash_matrix=@($crash); crash_matrix_pass=$allCrashPass; losing_fork_artifact_rejection=@($losingEvidence); same_backend_controls=@('s1-rocksdb-to-rocksdb','s2-sqlite-to-sqlite'); deeper_fork_control=@($deep); deeper_fork_control_recorded=(@($deep).Count -eq 2); artifact_remove_after_validation_tested=$artifact_remove_after_validation_tested; offline_exclusive_enforced=$offline_exclusive_enforced; simultaneous_imports_tested=$simultaneous_imports_tested; commit_inside_engine_exercised=$commit_inside_engine_exercised; core_matrix_pass=$coreMatrixPass
    verdict=$verdict
}
$manifest = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\manifests\rp2d-evidence-summary.json'
[System.IO.File]::WriteAllText($manifest, ($summary | ConvertTo-Json -Depth 100) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "RP2-D completed. Evidence: $RunRoot"
Write-Output "Summary: $manifest"
Write-Output "Verdict: $($summary.verdict)"
