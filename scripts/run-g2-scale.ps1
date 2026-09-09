param(
    [string]$Root = (Join-Path ((Get-Location).Path) ("_work\g2-scale-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [string[]]$Workloads = @('realistic-sparse', 'realistic-moderate', 'realistic-dense', 'stress-unique', 'stress-shared'),
    [ValidateRange(1, 10)]
    [int]$Repeats = 3,
    [string]$RocksWorker = '',
    [string]$SqliteWorker = ''
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Root = [System.IO.Path]::GetFullPath($Root)
$ResolvedProject = (Resolve-Path $ProjectRoot).Path
if (-not $Root.StartsWith($ResolvedProject, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "G2 output root must be inside the project: $Root"
}
if (Test-Path -LiteralPath $Root) {
    throw "Refusing to reuse an existing G2 output root: $Root"
}
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$CachedRocksOut = Join-Path $ProjectRoot 'target\debug\build\ckb-librocksdb-sys-13c1e69dba5090bb\out'
if (-not (Test-Path -LiteralPath $CachedRocksOut)) {
    throw "The retained cached RocksDB native output is missing: $CachedRocksOut"
}

$RocksTarget = Join-Path $Root 'build-rocksdb'
$SqliteTarget = Join-Path $Root 'build-sqlite'

function Build-Worker([string]$backend, [string]$target) {
    $env:CARGO_TARGET_DIR = $target
    if ($backend -eq 'sqlite') {
        & cargo test -p d2-script-handoff --no-default-features --features sqlite --offline --no-run
    } else {
        $env:D2_CACHED_ROCKSDB_OUT = $CachedRocksOut
        & cargo test -p d2-script-handoff --offline --no-run
    }
    if ($LASTEXITCODE -ne 0) {
        throw "G2 $backend worker build failed"
    }
}

function Find-Worker([string]$target) {
    $worker = Get-ChildItem -LiteralPath (Join-Path $target 'debug\deps') -File |
        Where-Object { $_.Name -match '^d2_script_handoff-[0-9a-f]+\.exe$' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $worker) {
        throw "D2 test worker not found under $target"
    }
    return $worker.FullName
}

if ($RocksWorker -and $SqliteWorker) {
    $Workers = @{ sqlite = (Resolve-Path -LiteralPath $SqliteWorker).Path; rocksdb = (Resolve-Path -LiteralPath $RocksWorker).Path }
} else {
    Build-Worker 'sqlite' $SqliteTarget
    Build-Worker 'rocksdb' $RocksTarget
    $Workers = @{ sqlite = Find-Worker $SqliteTarget; rocksdb = Find-Worker $RocksTarget }
}

function Invoke-G2Worker {
    param(
        [string]$Backend,
        [string]$Mode,
        [string]$Workload,
        [string]$Path,
        [string]$Artifact,
        [string]$Output,
        [int]$WorkerRepeats,
        [string]$Log
    )

    $parent = Split-Path -Parent $Output
    New-Item -ItemType Directory -Force -Path $parent, (Split-Path -Parent $Path) | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Workers[$Backend]
    $psi.Arguments = '--exact upstream::tests::g2_scale_worker --ignored --nocapture'
    $psi.WorkingDirectory = $ProjectRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['D2_G2_MODE'] = $Mode
    $psi.Environment['D2_G2_WORKLOAD'] = $Workload
    $psi.Environment['D2_G2_PATH'] = $Path
    $psi.Environment['D2_G2_REPEATS'] = $WorkerRepeats.ToString()
    $psi.Environment['D2_G2_OUTPUT'] = $Output
    if ($Artifact) {
        $psi.Environment['D2_G2_ARTIFACT'] = $Artifact
    } else {
        [void]$psi.Environment.Remove('D2_G2_ARTIFACT')
    }
    if ($Backend -eq 'rocksdb') {
        $psi.Environment['D2_CACHED_ROCKSDB_OUT'] = $CachedRocksOut
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $started = Get-Date
    if (-not $process.Start()) {
        throw "Unable to start G2 worker: $Backend/$Mode/$Workload"
    }
    $peakWorkingSet = [int64]0
    $peakCpuSeconds = [double]0
    while (-not $process.HasExited) {
        try {
            $sample = Get-Process -Id $process.Id -ErrorAction Stop
            if ([int64]$sample.WorkingSet64 -gt $peakWorkingSet) {
                $peakWorkingSet = [int64]$sample.WorkingSet64
            }
            if ([double]$sample.CPU -gt $peakCpuSeconds) {
                $peakCpuSeconds = [double]$sample.CPU
            }
        } catch {
            # The process can exit between HasExited and Get-Process.
        }
        Start-Sleep -Milliseconds 20
    }
    $process.WaitForExit()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $wallMs = [math]::Round(((Get-Date) - $started).TotalMilliseconds, 3)
    $stdout | Set-Content -LiteralPath ($Log + '.stdout.log') -Encoding utf8
    $stderr | Set-Content -LiteralPath ($Log + '.stderr.log') -Encoding utf8
    if ($process.ExitCode -ne 0) {
        throw "G2 worker failed: $Backend/$Mode/$Workload, exit $($process.ExitCode); see $Log.*"
    }
    if (-not (Test-Path -LiteralPath $Output)) {
        throw "G2 worker did not write its result: $Output"
    }
    $result = Get-Content -LiteralPath $Output -Raw | ConvertFrom-Json
    $result | Add-Member NoteProperty process_peak_working_set_bytes $peakWorkingSet
    $result | Add-Member NoteProperty process_cpu_ms ([math]::Round($peakCpuSeconds * 1000, 3))
    $result | Add-Member NoteProperty process_wall_ms $wallMs
    $result | Add-Member NoteProperty process_sample_interval_ms 20
    $result | Add-Member NoteProperty worker_backend $Backend
    $result | Add-Member NoteProperty worker_mode $Mode
    $result | Add-Member NoteProperty worker_result_path $Output
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Log -Encoding utf8
    return $result
}

$exports = @()
$imports = @()
$rescans = @()
foreach ($workload in $Workloads) {
    $workloadRoot = Join-Path $Root $workload
    New-Item -ItemType Directory -Force -Path $workloadRoot | Out-Null
    foreach ($sourceBackend in @('rocksdb', 'sqlite')) {
        $sourceRoot = Join-Path $workloadRoot ("source-" + $sourceBackend)
        $sourcePath = Join-Path $sourceRoot 'storage'
        $artifact = Join-Path $sourceRoot 'handoff.d2'
        $output = Join-Path $sourceRoot 'export.json'
        $export = Invoke-G2Worker -Backend $sourceBackend -Mode 'export' -Workload $workload `
            -Path $sourcePath -Artifact $artifact -Output $output -WorkerRepeats $Repeats `
            -Log (Join-Path $sourceRoot 'worker.log')
        $export | Add-Member NoteProperty source_backend $sourceBackend
        $exports += $export

        foreach ($destinationBackend in @('rocksdb', 'sqlite')) {
            for ($repetition = 1; $repetition -le $Repeats; $repetition++) {
                $destinationRoot = Join-Path $workloadRoot ("d2-" + $sourceBackend + '-to-' + $destinationBackend + '-run-' + $repetition)
                $destinationPath = Join-Path $destinationRoot 'storage'
                $prepareOutput = Join-Path $destinationRoot 'prepare.json'
                Invoke-G2Worker -Backend $destinationBackend -Mode 'prepare' -Workload $workload `
                    -Path $destinationPath -Artifact '' -Output $prepareOutput -WorkerRepeats 1 `
                    -Log (Join-Path $destinationRoot 'prepare.log') | Out-Null
                $importOutput = Join-Path $destinationRoot 'import.json'
                $import = Invoke-G2Worker -Backend $destinationBackend -Mode 'import' -Workload $workload `
                    -Path $destinationPath -Artifact $artifact -Output $importOutput -WorkerRepeats 1 `
                    -Log (Join-Path $destinationRoot 'import.log')
                $import | Add-Member NoteProperty source_backend $sourceBackend
                $import | Add-Member NoteProperty destination_backend $destinationBackend
                $import | Add-Member NoteProperty repetition $repetition
                $imports += $import
            }

            for ($repetition = 1; $repetition -le $Repeats; $repetition++) {
                $rescanRoot = Join-Path $workloadRoot ("rescan-" + $destinationBackend + '-run-' + $repetition)
                $rescanPath = Join-Path $rescanRoot 'storage'
                $rescanOutput = Join-Path $rescanRoot 'rescan.json'
                $rescan = Invoke-G2Worker -Backend $destinationBackend -Mode 'rescan' -Workload $workload `
                    -Path $rescanPath -Artifact '' -Output $rescanOutput -WorkerRepeats 1 `
                    -Log (Join-Path $rescanRoot 'rescan.log')
                $rescan | Add-Member NoteProperty destination_backend $destinationBackend
                $rescan | Add-Member NoteProperty repetition $repetition
                $rescans += $rescan
            }
        }
    }
}

$summary = [ordered]@{
    schema_version = 1
    experiment = 'D2-G2-scale-native-profile-synthetic'
    captured_local = (Get-Date).ToString('o')
    project_commit = (git -C $ProjectRoot rev-parse HEAD).Trim()
    upstream_profile = 'ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1'
    workload_names = $Workloads
    repeats = $Repeats
    measurement_note = 'Wall time and sampled process RSS/CPU are runner observations; preparation is separate from production D2 transfer timings.'
    exports = $exports
    imports = $imports
    rescans = $rescans
}
$summary | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $Root 'summary.json') -Encoding utf8
Write-Output "G2 scale evidence: $Root"
Write-Output "Summary: $(Join-Path $Root 'summary.json')"
