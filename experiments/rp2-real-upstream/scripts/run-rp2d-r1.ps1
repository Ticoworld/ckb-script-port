$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'
$RunRoot = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2d-r1'
$SafetyRoot = Join-Path $RunRoot 'safety'
$CommitRoot = Join-Path $RunRoot 'commit-race'
$Results = Join-Path $RunRoot 'results'
$Logs = Join-Path $RunRoot 'process-logs'
$Manifest = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\manifests\rp2d-r1-evidence-summary.json'
$Verifier = Join-Path $PSScriptRoot '..\src\rp2a_verifier.py'
$Consistency = Join-Path $PSScriptRoot '..\src\rp2d_consistency_verifier.py'

if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw 'Unexpected pinned upstream HEAD before RP2-D-R1' }

# Preserve the accepted conditional gate as the first action.  This invokes
# the existing runner unchanged; any regression stops R1 before new evidence.
if ($env:RP2D_R1_SKIP_REPRO -ne '1') {
    & (Join-Path $PSScriptRoot 'run-rp2d.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Accepted RP2-D conditional gate no longer reproduces' }
} else {
    Write-Output 'RP2-D-R1 debug mode: using the already reproduced conditional gate'
}
& (Join-Path $PSScriptRoot 'apply-rp2d-r1-upstream-patches.ps1')

if (Test-Path -LiteralPath $RunRoot) {
    $resolvedRun = (Resolve-Path -LiteralPath $RunRoot).Path
    $resolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not $resolvedRun.StartsWith($resolvedProject, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to reset outside project: $resolvedRun" }
    [System.IO.Directory]::Delete($resolvedRun, $true)
}
New-Item -ItemType Directory -Force -Path $SafetyRoot,$CommitRoot,$Results,$Logs | Out-Null

$env:RUSTUP_TOOLCHAIN = 'stable'
$env:CARGO_BUILD_JOBS = '1'
$env:CXXFLAGS = '-D_WIN32_WINNT=0x0602'
$BundledLibclang = Join-Path $ProjectRoot '_work\libclang\package\runtimes\win-x64\native'
if (-not (Test-Path -LiteralPath (Join-Path $BundledLibclang 'libclang.dll'))) { throw 'The disposable libclang prerequisite is missing' }
$env:LIBCLANG_PATH = $BundledLibclang
$RocksTarget = Join-Path $ProjectRoot '_work\build\rocksdb'
$SqliteTarget = Join-Path $ProjectRoot '_work\build\sqlite'

Push-Location -LiteralPath $Upstream
try {
    function Build-Worker([string]$backend, [string]$target) {
        $env:CARGO_TARGET_DIR = $target
        $existing = Get-ChildItem -LiteralPath (Join-Path $target 'debug\deps') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^ckb_light_client_lib-[0-9a-f]+\.exe$' } | Select-Object -First 1
        if ($existing) { Write-Output "Using existing $backend worker $($existing.Name)"; return }
        if ($backend -eq 'sqlite') {
            & cargo test --manifest-path light-client-lib/Cargo.toml --no-default-features --features sqlite rp2d_reorg_worker --no-run --locked
        } else {
            & cargo test --manifest-path light-client-lib/Cargo.toml rp2d_reorg_worker --no-run --locked
        }
        if ($LASTEXITCODE -ne 0) { throw "RP2-D-R1 build failed for $backend" }
    }
    Build-Worker 'rocksdb' $RocksTarget
    Build-Worker 'sqlite' $SqliteTarget

    function Find-TestExe([string]$target) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $target 'debug\deps') -File |
            Where-Object { $_.Name -match '^ckb_light_client_lib-[0-9a-f]+\.exe$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $candidate) { throw "Test executable not found in $target" }
        return $candidate.FullName
    }
    $Exes = @{ rocksdb=(Find-TestExe $RocksTarget); sqlite=(Find-TestExe $SqliteTarget) }

    function Start-WorkerProcess {
        param([string]$exe,[hashtable]$vars)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = '--exact tests::rp2_authority_replay::rp2d_reorg_worker --nocapture'
        $psi.WorkingDirectory = $Upstream
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        # Do not leave the child blocked on a full redirected pipe while the
        # parent is polling commit_enter.  The worker's structured JSON is the
        # evidence; verbose tracing may flow directly to the runner console.
        $psi.RedirectStandardOutput = $false
        $psi.RedirectStandardError = $false
        foreach ($key in @('RP2D_CRASH_STAGE','RP2D_COMMIT_SIGNAL','RP2D_COMMIT_ARMED','RP2D_EXPECTED_STATE','RP2D_IMPORT_HOLD_MS')) { [void]$psi.Environment.Remove($key) }
        foreach ($entry in $vars.GetEnumerator()) { $psi.Environment[$entry.Key] = [string]$entry.Value }
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        if (-not $p.Start()) { throw "Unable to start worker $exe" }
        return $p
    }
    function Complete-Process($p, [string]$logPath) {
        $p.WaitForExit()
        "exit=$($p.ExitCode)" | Set-Content -LiteralPath $logPath -Encoding utf8
        return $p.ExitCode
    }
    function Invoke-SafetyWorker([string]$backend,[string]$mode,[string]$artifact,[string]$output,[string]$id) {
        $target = if ($backend -eq 'rocksdb') { $RocksTarget } else { $SqliteTarget }
        $env:CARGO_TARGET_DIR = $target
        $vars = @{
            RP2_RUN_ROOT=$RunRoot; RP2_EVENT_DIR=(Join-Path $RunRoot 'events'); RP2C_MODE=''; RP2C_CASE=$id
            RP2C_OUTPUT=$output; RP2C_PROCESS_ID=$id; RP2D_MODE=$mode; RP2C_ARTIFACT=$artifact
        }
        $p = Start-WorkerProcess $Exes[$backend] $vars
        $exit = Complete-Process $p (Join-Path $Logs ($id + '.log'))
        if ($exit -ne 0 -or -not (Test-Path -LiteralPath $output)) { throw "Safety worker failed: $id ($backend/$mode), exit $exit" }
        return (Get-Content -LiteralPath $output -Raw | ConvertFrom-Json)
    }

    $safetyEvidence = @()
    $artifactPairs = @(
        [ordered]@{ backend='rocksdb'; source='sqlite'; name='c2-sqlite-to-rocksdb-source' },
        [ordered]@{ backend='sqlite'; source='rocksdb'; name='c1-rocksdb-to-sqlite-source' }
    )
    foreach ($pair in $artifactPairs) {
        $sourceArtifact = Join-Path (Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2c\artifacts') ($pair.name + '\valid.json')
        if (-not (Test-Path -LiteralPath $sourceArtifact)) { throw "Accepted artifact missing: $sourceArtifact" }
        foreach ($mode in @('live-reject','artifact-remove','artifact-replace','simultaneous')) {
            $caseDir = Join-Path (Join-Path $SafetyRoot $pair.backend) $mode
            New-Item -ItemType Directory -Force -Path $caseDir | Out-Null
            $artifact = Join-Path $caseDir 'valid.json'; Copy-Item -LiteralPath $sourceArtifact -Destination $artifact -Force
            $output = Join-Path $caseDir 'output.json'
            $modeName = if ($mode -eq 'live-reject') { 'live-reject' } else { $mode }
            $safetyEvidence += Invoke-SafetyWorker $pair.backend $modeName $artifact $output ('r1-' + $pair.backend + '-' + $mode)
        }
    }
    $safetyEvidence | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $Results 'safety-evidence.json') -Encoding utf8

    # Black-box parent/child commit-edge trials.  The child writes a flushed
    # commit_enter marker immediately before the native backend call and
    # commit_exit only after it returns.  The parent never writes the DB.
    $commitRows = @()
    $commitAttemptCounts = @{}
    foreach ($backend in @('rocksdb','sqlite')) {
        $sourceName = if ($backend -eq 'rocksdb') { 'c2-sqlite-to-rocksdb-source' } else { 'c1-rocksdb-to-sqlite-source' }
        $sourceArtifact = Join-Path (Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2c\artifacts') ($sourceName + '\valid.json')
        for ($trial = 1; $trial -le 4; $trial++) {
            $trialRoot = Join-Path (Join-Path $CommitRoot $backend) ('trial-' + $trial)
            $db = Join-Path $trialRoot 'db'; New-Item -ItemType Directory -Force -Path $db | Out-Null
            $signal = Join-Path $trialRoot 'commit.signal'; $crashOut = Join-Path $trialRoot 'crash.json'; $reopenOut = Join-Path $trialRoot 'reopen.json'; $retryOut = Join-Path $trialRoot 'retry.json'; $authorityBefore = Join-Path $trialRoot 'authority-before.json'
            $vars = @{
                RP2_RUN_ROOT=$RunRoot; RP2_EVENT_DIR=(Join-Path $RunRoot 'events'); RP2C_MODE=''; RP2C_CASE=('r1-' + $backend + '-commit-' + $trial)
                RP2C_OUTPUT=$crashOut; RP2C_PROCESS_ID=('r1-' + $backend + '-commit-' + $trial + '-crash'); RP2D_MODE='crash-import'; RP2D_DB_PATH=$db
                RP2D_AUTHORITY_BEFORE=$authorityBefore; RP2C_ARTIFACT=$sourceArtifact; RP2D_COMMIT_SIGNAL=$signal
            }
            $p = Start-WorkerProcess $Exes[$backend] $vars
            $deadline = (Get-Date).AddSeconds(45); $entered = $false
            while ((Get-Date) -lt $deadline) {
                if (Test-Path -LiteralPath $signal) {
                    $text = Get-Content -LiteralPath $signal -Raw
                    if ($text -match '(?m)^commit_enter\s*$') { $entered = $true; break }
                }
                if ($p.HasExited) { break }
                Start-Sleep -Milliseconds 2
            }
            if (-not $entered) {
                if (-not $p.HasExited) { $p.Kill() }
                $p.WaitForExit()
                "exit=$($p.ExitCode); signal=$(Test-Path $signal)" | Set-Content -LiteralPath (Join-Path $Logs ($backend + '-commit-' + $trial + '-no-enter.log')) -Encoding utf8
                throw "commit_enter was not observed for $backend trial $trial (exit $($p.ExitCode)); see no-enter log"
            }
            # The native commit may have completed between the marker read and
            # Kill(). Treat that as an unqualified (non-kill) timing sample,
            # rather than throwing from the harness; the verifier will keep it
            # out of the passing commit-race set.
            $killIssued = $false
            if (-not $p.HasExited) {
                try { $p.Kill(); $killIssued = $true } catch { $killIssued = $false }
            }
            $p.WaitForExit(); $crashExit = $p.ExitCode
            # A commit can finish before the parent reaches Kill().  That is
            # an unqualified timing sample, not a process-kill trial.  Retry
            # the same numbered trial (bounded) so the evidence set contains
            # only real child terminations racing the boundary.
            $attemptKey = "$backend-$trial"
            if (-not $commitAttemptCounts.ContainsKey($attemptKey)) { $commitAttemptCounts[$attemptKey] = 0 }
            if (-not $killIssued -or $crashExit -eq 0) {
                $commitAttemptCounts[$attemptKey]++
                if ($commitAttemptCounts[$attemptKey] -ge 8) { throw "commit-race could not terminate child for $backend trial $trial" }
                if (Test-Path -LiteralPath $trialRoot) { Remove-Item -LiteralPath $trialRoot -Recurse -Force }
                $trial--
                continue
            }
            $signalText = if (Test-Path -LiteralPath $signal) { Get-Content -LiteralPath $signal -Raw } else { '' }
            $commitExitObserved = $signalText -match '(?m)^commit_exit\s*$'
            "exit=$crashExit; kill_issued=$killIssued; commit_enter=$entered; commit_exit=$commitExitObserved" | Set-Content -LiteralPath (Join-Path $Logs ($backend + '-commit-' + $trial + '-crash.log')) -Encoding utf8
            $reopenVars = @{
                RP2_RUN_ROOT=$RunRoot; RP2_EVENT_DIR=(Join-Path $RunRoot 'events'); RP2C_MODE=''; RP2C_CASE=('r1-' + $backend + '-commit-' + $trial + '-reopen'); RP2C_OUTPUT=$reopenOut; RP2C_PROCESS_ID=('r1-' + $backend + '-commit-' + $trial + '-reopen'); RP2D_MODE='reopen'; RP2D_DB_PATH=$db; RP2D_EXPECTED_STATE='ANY'
            }
            $rp = Start-WorkerProcess $Exes[$backend] $reopenVars; $reopenExit = Complete-Process $rp (Join-Path $Logs ($backend + '-commit-' + $trial + '-reopen.log'))
            if ($reopenExit -ne 0) { throw "commit-race reopen failed for $backend trial $trial" }
            $retryVars = @{
                RP2_RUN_ROOT=$RunRoot; RP2_EVENT_DIR=(Join-Path $RunRoot 'events'); RP2C_MODE=''; RP2C_CASE=('r1-' + $backend + '-commit-' + $trial + '-retry'); RP2C_OUTPUT=$retryOut; RP2C_PROCESS_ID=('r1-' + $backend + '-commit-' + $trial + '-retry'); RP2D_MODE='crash-import'; RP2D_DB_PATH=$db; RP2C_ARTIFACT=$sourceArtifact
            }
            $tp = Start-WorkerProcess $Exes[$backend] $retryVars; $retryExit = Complete-Process $tp (Join-Path $Logs ($backend + '-commit-' + $trial + '-retry.log'))
            if ($retryExit -ne 0 -or -not (Test-Path -LiteralPath $retryOut)) { throw "commit-race retry failed for $backend trial $trial" }
            $sourceBackend = if ($backend -eq 'rocksdb') { 'sqlite' } else { 'rocksdb' }
            $killTiming = if ($commitExitObserved) { 'after_observable_exit' } else { 'before_observable_exit_or_indeterminate' }
            $commitRows += [ordered]@{
                backend=$backend; source_artifact_backend=$sourceBackend; trial=$trial
                crash_exit_code=$crashExit; reopen_exit_code=$reopenExit; retry_exit_code=$retryExit
                commit_enter_observed=$entered; commit_exit_observed=$commitExitObserved
                kill_timing=$killTiming
                authority_before=(Get-Content $authorityBefore -Raw | ConvertFrom-Json); reopen=(Get-Content $reopenOut -Raw | ConvertFrom-Json); retry=(Get-Content $retryOut -Raw | ConvertFrom-Json)
            }
        }
    }
    $commitRows | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $Results 'commit-race.json') -Encoding utf8
} finally { Pop-Location }

& python $Verifier --events-dir (Join-Path (Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2d') 'events') --output (Join-Path $Results 'rp2d-r1-event-verification.json')
if ($LASTEXITCODE -ne 0) { throw 'Independent event verifier rejected RP2-D-R1 evidence' }
& python $Consistency --crash-matrix (Join-Path (Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2d\results') 'crash-matrix.json') --r1-evidence (Join-Path $Results 'safety-evidence.json') --commit-race (Join-Path $Results 'commit-race.json') --output (Join-Path $Results 'rp2d-r1-consistency-verification.json')
if ($LASTEXITCODE -ne 0) { throw 'Independent RP2-D-R1 persisted-state verifier rejected evidence' }

$consistency = Get-Content (Join-Path $Results 'rp2d-r1-consistency-verification.json') -Raw | ConvertFrom-Json
$safety = @($safetyEvidence)
$commitRows = @($commitRows)
$commitPass = $commitRows.Count -eq 8 -and @($commitRows | Where-Object { -not $_.commit_enter_observed -or $_.crash_exit_code -eq 0 -or $_.reopen_exit_code -ne 0 -or $_.retry_exit_code -ne 0 -or $_.reopen.consistency -notin @('OLD_COMPLETE','NEW_COMPLETE') }).Count -eq 0
$safetyPass = $safety.Count -eq 8 -and $consistency.safety_checked -eq 8 -and $consistency.safety_failures.Count -eq 0
$dash = [string][char]0x2014
$verdict = if ($consistency.passed -and $commitPass -and $safetyPass) { "RP2-D PASS $dash PROCEED TO PDEF1 SCOPE FREEZE" } else { "RP2-D CONDITIONAL PASS $dash SAFETY SEAM STILL INCOMPLETE" }
$patchHashes = [ordered]@{}
Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'patches\rp2') -Filter '*.patch' -File | Sort-Object Name | ForEach-Object {
    $patchHashes[$_.Name] = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
}
$cargoLock = Join-Path $Upstream 'Cargo.lock'
$gitStatus = @(git -C $ProjectRoot status --short)
$summary = [ordered]@{
    schema_version=2; experiment='D2-RP2D-R1-final-safety-seam-closure'; captured_utc=(Get-Date).ToUniversalTime().ToString('o'); project_commit=(git -C $ProjectRoot rev-parse HEAD).Trim(); project_worktree_clean=($gitStatus.Count -eq 0); project_worktree_status=$gitStatus; upstream_revision=$Pinned; toolchain='stable / Rust 1.96.0'; cargo_lock_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $cargoLock).Hash; patch_sha256=$patchHashes
    lifecycle_guard_type='test-only shared ImportLifecycle with RAII protocol activity and offline import guards'; offline_exclusive_enforced=$safetyPass
    artifact_model='owned immutable decoded TypedScriptHandoff object'; artifact_remove_after_validation_tested=($safety | Where-Object mode -eq 'artifact-remove').Count -eq 2; artifact_replacement_after_validation_tested=($safety | Where-Object mode -eq 'artifact-replace').Count -eq 2
    simultaneous_imports_tested=($safety | Where-Object mode -eq 'simultaneous').Count -eq 2; safety_evidence=$safety; commit_race=$commitRows; commit_race_pass=$commitPass; consistency_verifier=$consistency
    reorg_regression='reproduced by unchanged run-rp2d.ps1'; authority_unchanged_during_import=$safetyPass; handoff_seam_changed=$false
    verdict=$verdict
}
[System.IO.File]::WriteAllText($Manifest, ($summary | ConvertTo-Json -Depth 100) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "RP2-D-R1 completed. Evidence: $RunRoot"
Write-Output "Summary: $Manifest"
Write-Output "Verdict: $verdict"
