$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$RunRoot = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run-rp2c'
$Events = Join-Path $RunRoot 'events'
$Fixture = Join-Path $RunRoot 'fixture'
$Results = Join-Path $RunRoot 'results'
$Artifacts = Join-Path $RunRoot 'artifacts'
$Logs = Join-Path $RunRoot 'process-logs'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'
$Rp2bScript = Join-Path $PSScriptRoot 'run-rp2b.ps1'
$ApplyScript = Join-Path $PSScriptRoot 'apply-rp2c-upstream-patches.ps1'
$Verifier = Join-Path $PSScriptRoot '..\src\rp2a_verifier.py'
$Comparator = Join-Path $PSScriptRoot '..\src\compare_rp2c.py'

if (-not (Test-Path -LiteralPath $Upstream)) {
    throw "Pinned upstream checkout is missing: $Upstream"
}
$Head = (git -C $Upstream rev-parse HEAD).Trim()
if ($Head -ne $Pinned) {
    throw "Unexpected upstream HEAD: $Head"
}

# Re-run the accepted measuring instrument and same-backend handoff before the
# transport experiment.  This is intentionally a separate run root.
& $Rp2bScript
if ($LASTEXITCODE -ne 0) {
    throw 'RP2-A/RP2-B reproduction failed; cross-backend testing is blocked'
}
& $ApplyScript

if (Test-Path -LiteralPath $RunRoot) {
    $ResolvedRun = (Resolve-Path -LiteralPath $RunRoot).Path
    $ResolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not $ResolvedRun.StartsWith($ResolvedProject, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to reset a run root outside the project: $ResolvedRun"
    }
    [System.IO.Directory]::Delete($ResolvedRun, $true)
}
New-Item -ItemType Directory -Force -Path $Events, $Fixture, $Results, $Artifacts, $Logs | Out-Null

Push-Location -LiteralPath $Upstream
try {
    $env:RUSTUP_TOOLCHAIN = 'stable'
    $env:CARGO_BUILD_JOBS = '1'
    $env:CXXFLAGS = '-D_WIN32_WINNT=0x0602'
    $BundledLibclang = Join-Path $ProjectRoot '_work\libclang\package\runtimes\win-x64\native'
    if (Test-Path -LiteralPath (Join-Path $BundledLibclang 'libclang.dll')) {
        $env:LIBCLANG_PATH = $BundledLibclang
    } elseif (-not $env:LIBCLANG_PATH) {
        throw 'LIBCLANG_PATH is not set and the documented disposable libclang prerequisite is missing'
    }

    $BuildEvidence = [ordered]@{
        schema_version = 1
        experiment = 'D2-RP2C-cross-backend-semantic-portability'
        upstream_revision = $Pinned
        cargo_lock_sha256 = (Get-FileHash (Join-Path $Upstream 'Cargo.lock') -Algorithm SHA256).Hash
        rustc = (& rustc --version)
        cargo = (& cargo --version)
        builds = @()
    }

    function Invoke-Rp2cBuild {
        param([string]$Backend, [string]$TargetDir, [string[]]$CargoArgs)
        $env:CARGO_TARGET_DIR = $TargetDir
        $start = Get-Date
        & cargo @CargoArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Cargo build failed for $Backend with exit code $LASTEXITCODE"
        }
        $artifacts = @(Get-ChildItem -LiteralPath (Join-Path $TargetDir 'debug\deps') -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'ckb_light_client_lib.*(exe|dll|rlib|rmeta)$' } |
            ForEach-Object {
                $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
                [ordered]@{ path = $_.FullName; sha256 = $hash.Hash; bytes = $_.Length }
            })
        $BuildEvidence.builds += [ordered]@{
            backend = $Backend
            target_dir = $TargetDir
            command = ('cargo ' + ($CargoArgs -join ' '))
            started_utc = $start.ToUniversalTime().ToString('o')
            completed_utc = (Get-Date).ToUniversalTime().ToString('o')
            artifacts = @($artifacts)
        }
    }

    # RP2-A/RP2-B already compiled these exact feature-specific trees with
    # the accepted RP2-C test seam present. Reusing them keeps this runner
    # deterministic without rebuilding native RocksDB from scratch.
    $RocksTarget = Join-Path $ProjectRoot '_work\build\rocksdb'
    $SqliteTarget = Join-Path $ProjectRoot '_work\build\sqlite'
    Invoke-Rp2cBuild -Backend 'rocksdb' -TargetDir $RocksTarget -CargoArgs @('test','--manifest-path','light-client-lib/Cargo.toml','rp2c_cross_backend_worker','--no-run','--locked')
    Invoke-Rp2cBuild -Backend 'sqlite' -TargetDir $SqliteTarget -CargoArgs @('test','--manifest-path','light-client-lib/Cargo.toml','--no-default-features','--features','sqlite','rp2c_cross_backend_worker','--no-run','--locked')
    $BuildEvidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $RunRoot 'build-evidence.json') -Encoding utf8

    function Invoke-Rp2cWorker {
        param(
            [string]$Backend,
            [string]$TargetDir,
            [string]$Mode,
            [string]$Case,
            [string]$Output,
            [string]$Artifact,
            [string]$ProcessId
        )
        $env:CARGO_TARGET_DIR = $TargetDir
        $env:RP2_RUN_ROOT = $RunRoot
        $env:RP2_EVENT_DIR = $Events
        $env:RP2_FIXTURE_ROOT = $Fixture
        $env:RP2C_MODE = $Mode
        $env:RP2C_CASE = $Case
        $env:RP2C_OUTPUT = $Output
        $env:RP2C_PROCESS_ID = $ProcessId
        $env:RP2C_ARTIFACT_DIR = $Artifacts
        if ($Artifact) { $env:RP2C_ARTIFACT = $Artifact } else { Remove-Item Env:RP2C_ARTIFACT -ErrorAction SilentlyContinue }

        if ($Backend -eq 'sqlite') {
            $args = @('test','--manifest-path','light-client-lib/Cargo.toml','--no-default-features','--features','sqlite','rp2c_cross_backend_worker','--','--test-threads=1','--nocapture')
        } else {
            $args = @('test','--manifest-path','light-client-lib/Cargo.toml','rp2c_cross_backend_worker','--','--test-threads=1','--nocapture')
        }
        $started = Get-Date
        # PowerShell represents cargo's normal stderr progress as a
        # NativeCommandError. Capture it without converting a successful
        # cargo exit into a script exception; the explicit exit check below is
        # the worker failure gate.
        $savedErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $lines = @(& cargo @args 2>&1 | ForEach-Object { $_.ToString() })
        $ErrorActionPreference = $savedErrorActionPreference
        $exit = $LASTEXITCODE
        $logPath = Join-Path $Logs ($ProcessId + '.log')
        $lines | Set-Content -LiteralPath $logPath -Encoding utf8
        $lines | Where-Object { $_ -match 'running [0-9]+ test|test result|FAILED|error\[' } | ForEach-Object { Write-Host $_ }
        if ($exit -ne 0) {
            throw "RP2-C worker failed: $ProcessId ($Backend/$Mode), exit $exit. See $logPath"
        }
        if (-not (Test-Path -LiteralPath $Output)) {
            throw "RP2-C worker did not write its result: $Output"
        }
        return [ordered]@{
            process_id = $ProcessId
            backend = $Backend
            mode = $Mode
            case = $Case
            command = ('cargo ' + ($args -join ' '))
            started_utc = $started.ToUniversalTime().ToString('o')
            completed_utc = (Get-Date).ToUniversalTime().ToString('o')
            log = $logPath
            output = $Output
        }
    }

    $allProcesses = @()
    $directions = @(
        [ordered]@{
            name = 'c1-rocksdb-to-sqlite'
            source_backend = 'rocksdb'
            destination_backend = 'sqlite'
            source_target = $RocksTarget
            destination_target = $SqliteTarget
        },
        [ordered]@{
            name = 'c2-sqlite-to-rocksdb'
            source_backend = 'sqlite'
            destination_backend = 'rocksdb'
            source_target = $SqliteTarget
            destination_target = $RocksTarget
        }
    )

    foreach ($direction in $directions) {
        $slug = $direction.name
        $sourceRoot = Join-Path $Artifacts ($slug + '-source')
        $validArtifact = Join-Path $sourceRoot 'valid.json'
        $sourceResult = Join-Path $Results ($slug + '-source.json')
        $baselineResult = Join-Path $Results ($slug + '-baseline.json')
        $importResult = Join-Path $Results ($slug + '-import.json')
        $tamperedResult = Join-Path $Results ($slug + '-import-tampered-backend.json')

        $allProcesses += Invoke-Rp2cWorker $direction.source_backend $direction.source_target 'export' ($slug + '-source') $sourceResult $validArtifact ($slug + '-source-' + $direction.source_backend)
        $allProcesses += Invoke-Rp2cWorker $direction.destination_backend $direction.destination_target 'baseline' ($slug + '-baseline') $baselineResult '' ($slug + '-baseline-' + $direction.destination_backend)
        $allProcesses += Invoke-Rp2cWorker $direction.destination_backend $direction.destination_target 'import' ($slug + '-import') $importResult $validArtifact ($slug + '-import-' + $direction.destination_backend)
        $allProcesses += Invoke-Rp2cWorker $direction.destination_backend $direction.destination_target 'import' ($slug + '-import-tampered-backend') $tamperedResult (Join-Path $sourceRoot 'tampered-backend.json') ($slug + '-import-tampered-' + $direction.destination_backend)

        $compareResult = Join-Path $Results ($slug + '-comparison.json')
        & python $Comparator --case $slug --source $sourceResult --baseline $baselineResult --import $importResult --tampered $tamperedResult --output $compareResult
        if ($LASTEXITCODE -ne 0) {
            throw "RP2-C semantic comparison failed for $slug"
        }

        $negativeNames = @(
            'truncated', 'digest-mismatch', 'duplicate-item', 'wrong-version',
            'reordered', 'wrong-genesis', 'wrong-handoff-hash', 'wrong-script',
            'wrong-role', 'cursor-beyond', 'forged-c-state'
        )
        foreach ($negativeName in $negativeNames) {
            $negativeArtifact = Join-Path $sourceRoot ($negativeName + '.json')
            $negativeResult = Join-Path $Results ($slug + '-negative-' + $negativeName + '.json')
            $negativeCase = $slug + '-negative-' + $negativeName
            $allProcesses += Invoke-Rp2cWorker $direction.destination_backend $direction.destination_target 'negative' $negativeCase $negativeResult $negativeArtifact ($negativeCase + '-' + $direction.destination_backend)
        }
    }

    $allProcesses | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Results 'processes.json') -Encoding utf8
} finally {
    Pop-Location
}

& python $Verifier --events-dir $Events --output (Join-Path $Results 'rp2c-verification.json')
if ($LASTEXITCODE -ne 0) {
    throw 'Independent RP2-A/RP2-B/RP2-C event verifier rejected the run'
}

$comparisonC1 = Get-Content (Join-Path $Results 'c1-rocksdb-to-sqlite-comparison.json') -Raw | ConvertFrom-Json
$comparisonC2 = Get-Content (Join-Path $Results 'c2-sqlite-to-rocksdb-comparison.json') -Raw | ConvertFrom-Json
$verification = Get-Content (Join-Path $Results 'rp2c-verification.json') -Raw | ConvertFrom-Json
$negativeEvidence = [ordered]@{}
foreach ($directionName in @('c1-rocksdb-to-sqlite', 'c2-sqlite-to-rocksdb')) {
    $negativeEvidence[$directionName] = @()
    foreach ($negativeName in @(
        'truncated', 'digest-mismatch', 'duplicate-item', 'wrong-version',
        'reordered', 'wrong-genesis', 'wrong-handoff-hash', 'wrong-script',
        'wrong-role', 'cursor-beyond', 'forged-c-state'
    )) {
        $negativePath = Join-Path $Results ($directionName + '-negative-' + $negativeName + '.json')
        $negative = Get-Content $negativePath -Raw | ConvertFrom-Json
        $negativeEvidence[$directionName] += [ordered]@{
            case = $negative.case
            backend = $negative.backend
            rejected = $negative.rejected
            reason = $negative.reason
            authority_unchanged = $negative.authority_unchanged
            destination_scripts_empty = $negative.destination_scripts_empty
        }
    }
}
$buildEvidence = Get-Content (Join-Path $RunRoot 'build-evidence.json') -Raw | ConvertFrom-Json
$summary = [ordered]@{
    schema_version = 1
    experiment = 'D2-RP2C-cross-backend-semantic-portability'
    captured_utc = (Get-Date).ToUniversalTime().ToString('o')
    project_commit = (git -C $ProjectRoot rev-parse HEAD).Trim()
    upstream_revision = $Pinned
    artifact_version = 'rp2-cross-backend-fixture-v1'
    builds = $buildEvidence
    accepted_patch_sha256 = [ordered]@{
        '0002-rp2b-typed-script-handoff.patch' = (Get-FileHash (Join-Path $ProjectRoot 'patches\rp2\0002-rp2b-typed-script-handoff.patch') -Algorithm SHA256).Hash
        '0003-rp2b-spendable-fixture.patch' = (Get-FileHash (Join-Path $ProjectRoot 'patches\rp2\0003-rp2b-spendable-fixture.patch') -Algorithm SHA256).Hash
        '0004-rp2c-cross-backend-transport.patch' = (Get-FileHash (Join-Path $ProjectRoot 'patches\rp2\0004-rp2c-cross-backend-transport.patch') -Algorithm SHA256).Hash
    }
    cases = [ordered]@{
        C1 = $comparisonC1
        C2 = $comparisonC2
    }
    verifier = $verification
    processes = @(Get-Content (Join-Path $Results 'processes.json') -Raw | ConvertFrom-Json)
    cross_backend_adversaries = $negativeEvidence
    verdict = if ($comparisonC1.checks.PSObject.Properties.Value -notcontains $false -and $comparisonC2.checks.PSObject.Properties.Value -notcontains $false -and $verification.passed) { 'RP2-C PASS — PROCEED TO RP2-D REORG + CRASH' } else { 'RP2-C PARTIAL — CROSS-BACKEND REPAIR REQUIRED' }
}
$summary.verdict = if ($comparisonC1.checks.PSObject.Properties.Value -notcontains $false -and $comparisonC2.checks.PSObject.Properties.Value -notcontains $false -and $verification.passed) { [string]::Concat('RP2-C PASS ', [char]0x2014, ' PROCEED TO RP2-D REORG + CRASH') } else { [string]::Concat('RP2-C PARTIAL ', [char]0x2014, ' CROSS-BACKEND REPAIR REQUIRED') }
$Manifest = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\manifests\rp2c-evidence-summary.json'
$summaryJson = $summary | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($Manifest, $summaryJson + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "RP2-C completed. Evidence: $RunRoot"
Write-Output "Summary: $Manifest"
Write-Output "Verdict: $($summary.verdict)"
