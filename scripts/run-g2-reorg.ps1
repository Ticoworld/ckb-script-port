param(
    [Parameter(Mandatory = $true)]
    [string] $UpstreamExe,

    [Parameter(Mandatory = $true)]
    [string] $D2Exe,

    [Parameter(Mandatory = $true)]
    [string] $Artifact,

    [Parameter(Mandatory = $true)]
    [string] $Root,

    [int] $ForkPoint = 30,
    [int] $NewTip = 40
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$upstream = (Resolve-Path -LiteralPath $UpstreamExe).Path
$d2 = (Resolve-Path -LiteralPath $D2Exe).Path
$artifactPath = (Resolve-Path -LiteralPath $Artifact).Path
$rootPath = [IO.Path]::GetFullPath($Root)
$projectPath = [IO.Path]::GetFullPath($repo)
if (!$rootPath.StartsWith($projectPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "G2 reorg root must be inside the project: $rootPath"
}
if (Test-Path -LiteralPath $rootPath) {
    throw "Refusing to reuse an existing G2 reorg root: $rootPath"
}
if ($NewTip -lt $ForkPoint + 3) { throw 'NewTip must leave proposal, blank, and inclusion blocks' }
New-Item -ItemType Directory -Force -Path $rootPath | Out-Null
$destinationStorage = Join-Path $rootPath 'destination-storage'
$destinationChainDb = Join-Path $rootPath 'destination-chain-db'
$evidence = Join-Path $rootPath 'evidence'
New-Item -ItemType Directory -Force -Path $destinationStorage, $destinationChainDb, $evidence | Out-Null

function Invoke-Upstream {
    param([string] $Mode, [string] $Output, [string] $Log)
    $env:RP2C_MODE = $Mode
    $env:RP2C_CASE = 'g2-production-bounded-deep-reorg'
    $env:RP2C_DESTINATION_STORAGE = $destinationStorage
    $env:RP2C_DESTINATION_CHAIN_DB = $destinationChainDb
    $env:RP2C_METADATA = Join-Path $evidence 'metadata.json'
    $env:RP2C_OUTPUT = $Output
    $env:RP2C_REORG_OUTPUT = Join-Path $evidence 'reorg.json'
    $env:G2_FORK_POINT = $ForkPoint.ToString()
    $env:G2_NEW_TIP = $NewTip.ToString()
    $previousErrorAction = $ErrorActionPreference
    try {
        # The diagnostic intentionally makes the upstream peer emit a ban
        # message on stderr. Capture it without treating expected rejection
        # logging as a PowerShell exception; the test exit code remains the
        # authoritative result.
        $ErrorActionPreference = 'Continue'
        & $upstream 'tests::rp2_authority_replay::g1_production_protocol_worker' '--exact' '--ignored' '--nocapture' *> $Log
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) { throw "upstream worker $Mode failed; see $Log" }
}

Invoke-Upstream 'prepare-destination' (Join-Path $evidence 'prepare-destination.json') (Join-Path $evidence 'prepare-destination.log')
$env:D2_G1_MODE = 'import'
$env:D2_G1_STORAGE = $destinationStorage
$env:D2_G1_ARTIFACT = $artifactPath
$env:D2_G1_WORKER_RESULT = Join-Path $evidence 'd2-import.json'
& $d2 'upstream::tests::production_g1_external_worker' '--exact' '--ignored' '--nocapture' *> (Join-Path $evidence 'd2-import.log')
if ($LASTEXITCODE -ne 0) { throw 'production D2 import failed; see evidence/d2-import.log' }

Invoke-Upstream 'reorg-deep-diagnostic' (Join-Path $evidence 'reorg.json') (Join-Path $evidence 'reorg.log')
Invoke-Upstream 'reorg-deep-diagnostic-reopen' (Join-Path $evidence 'reorg-reopen.json') (Join-Path $evidence 'reorg-reopen.log')
$result = Get-Content -LiteralPath (Join-Path $evidence 'reorg-reopen.json') -Raw | ConvertFrom-Json
if (!$result.restart_coherent -or !$result.rejected_fork_state_coherent) {
    throw 'bounded deep reorg result failed final assertions'
}
Write-Output "production bounded deep reorg rejection/envelope passed; evidence: $evidence"
exit 0
