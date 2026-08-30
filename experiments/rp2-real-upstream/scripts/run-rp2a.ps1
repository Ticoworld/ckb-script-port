$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$RunRoot = Join-Path $ProjectRoot 'experiments\rp2-real-upstream\run'
$Events = Join-Path $RunRoot 'events'
$Fixture = Join-Path $RunRoot 'fixture'
$Results = Join-Path $RunRoot 'results'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'

if (-not (Test-Path -LiteralPath $Upstream)) {
    throw "Pinned upstream checkout is missing: $Upstream"
}
$Head = (git -C $Upstream rev-parse HEAD).Trim()
if ($Head -ne $Pinned) {
    throw "Unexpected upstream HEAD: $Head"
}

if (Test-Path -LiteralPath $RunRoot) {
    $ResolvedRun = (Resolve-Path -LiteralPath $RunRoot).Path
    $ResolvedProject = (Resolve-Path -LiteralPath $ProjectRoot).Path
    if (-not $ResolvedRun.StartsWith($ResolvedProject, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to reset a run root outside the project: $ResolvedRun"
    }
    [System.IO.Directory]::Delete($ResolvedRun, $true)
}
New-Item -ItemType Directory -Force -Path $Events, $Fixture, $Results | Out-Null

& (Join-Path $PSScriptRoot 'apply-rp2a-upstream-patches.ps1')
Push-Location -LiteralPath $Upstream

$env:RUSTUP_TOOLCHAIN = 'stable'
$env:CARGO_BUILD_JOBS = '1'
$env:CXXFLAGS = '-D_WIN32_WINNT=0x0602'
$BundledLibclang = Join-Path $ProjectRoot '_work\libclang\package\runtimes\win-x64\native'
if (Test-Path -LiteralPath (Join-Path $BundledLibclang 'libclang.dll')) {
    $env:LIBCLANG_PATH = $BundledLibclang
} elseif (-not $env:LIBCLANG_PATH) {
    throw 'LIBCLANG_PATH is not set and the documented disposable libclang prerequisite is missing'
}
$env:RP2_RUN_ROOT = $RunRoot
$env:RP2_EVENT_DIR = $Events
$env:RP2_FIXTURE_ROOT = $Fixture

$BuildEvidence = [ordered]@{
    schema_version = 1
    upstream_revision = $Head
    cargo_lock_sha256 = (Get-FileHash (Join-Path $Upstream 'Cargo.lock') -Algorithm SHA256).Hash
    rustc = (& rustc --version)
    cargo = (& cargo --version)
    builds = @()
}

function Invoke-Rp2Cargo {
    param(
        [string]$Backend,
        [string]$TargetDir,
        [string[]]$CargoArgs
    )
    $env:CARGO_TARGET_DIR = $TargetDir
    $start = Get-Date
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & cargo @CargoArgs
    $cargoExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($cargoExitCode -ne 0) {
        throw "Cargo build failed for $Backend with exit code $cargoExitCode"
    }
    $artifacts = @(Get-ChildItem -LiteralPath (Join-Path $TargetDir 'debug\deps') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'ckb_light_client_lib.*(exe|dll|rlib|rmeta)$' } |
        Select-Object -ExpandProperty FullName)
    $BuildEvidence.builds += [ordered]@{
        backend = $Backend
        target_dir = $TargetDir
        command = ('cargo ' + ($CargoArgs -join ' '))
        started_utc = $start.ToUniversalTime().ToString('o')
        completed_utc = (Get-Date).ToUniversalTime().ToString('o')
        artifacts = @($artifacts | ForEach-Object {
            $hash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
            [ordered]@{ path = $_; sha256 = $hash.Hash; bytes = (Get-Item -LiteralPath $_).Length }
        })
    }
}

Invoke-Rp2Cargo -Backend 'rocksdb' -TargetDir (Join-Path $ProjectRoot '_work\build\rocksdb') -CargoArgs @('test','--manifest-path','light-client-lib/Cargo.toml','--no-run','--locked')
Invoke-Rp2Cargo -Backend 'sqlite' -TargetDir (Join-Path $ProjectRoot '_work\build\sqlite') -CargoArgs @('test','--manifest-path','light-client-lib/Cargo.toml','--no-run','--no-default-features','--features','sqlite','--locked')

$BuildEvidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RunRoot 'build-evidence.json') -Encoding utf8

function Invoke-Rp2Tests {
    param([string]$Backend, [string]$TargetDir, [switch]$Sqlite)
    $env:CARGO_TARGET_DIR = $TargetDir
    $cargoTestArguments = @('test','--manifest-path','light-client-lib/Cargo.toml','rp2a_','--','--test-threads=1','--nocapture')
    if ($Sqlite) {
        $cargoTestArguments = @('test','--manifest-path','light-client-lib/Cargo.toml','--no-default-features','--features','sqlite','rp2a_','--','--test-threads=1','--nocapture')
    }
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & cargo @cargoTestArguments
    $cargoExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorActionPreference
    if ($cargoExitCode -ne 0) {
        throw "RP2-A tests failed for $Backend with exit code $cargoExitCode"
    }
}

Invoke-Rp2Tests -Backend 'rocksdb' -TargetDir (Join-Path $ProjectRoot '_work\build\rocksdb')
Invoke-Rp2Tests -Backend 'sqlite' -TargetDir (Join-Path $ProjectRoot '_work\build\sqlite') -Sqlite
Pop-Location

$Verifier = Join-Path $PSScriptRoot '..\src\rp2a_verifier.py'
& python $Verifier --events-dir $Events --output (Join-Path $Results 'rp2a-verification.json')
if ($LASTEXITCODE -ne 0) {
    throw "Independent RP2-A evidence verifier rejected the run"
}

Write-Output "RP2-A completed. Evidence: $RunRoot"
