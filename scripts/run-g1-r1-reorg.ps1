param(
    [Parameter(Mandatory = $true)]
    [string] $UpstreamExe,

    [Parameter(Mandatory = $true)]
    [string] $D2Exe,

    [Parameter(Mandatory = $true)]
    [string] $Artifact,

    [Parameter(Mandatory = $true)]
    [string] $Root
)

$ErrorActionPreference = 'Stop'
$upstream = (Resolve-Path -LiteralPath $UpstreamExe).Path
$d2 = (Resolve-Path -LiteralPath $D2Exe).Path
$artifactPath = (Resolve-Path -LiteralPath $Artifact).Path
$rootPath = [IO.Path]::GetFullPath($Root)
$destinationStorage = Join-Path $rootPath 'destination-storage'
$destinationChainDb = Join-Path $rootPath 'destination-chain-db'
$evidence = Join-Path $rootPath 'evidence'
New-Item -ItemType Directory -Force -Path $destinationStorage, $destinationChainDb, $evidence | Out-Null

function Invoke-Upstream {
    param([string] $Mode, [string] $Output, [string] $Log)
    $env:RP2C_MODE = $Mode
    $env:RP2C_CASE = 'g1-r1-production-shallow-reorg'
    $env:RP2C_DESTINATION_STORAGE = $destinationStorage
    $env:RP2C_DESTINATION_CHAIN_DB = $destinationChainDb
    $env:RP2C_METADATA = Join-Path $evidence 'metadata.json'
    $env:RP2C_OUTPUT = $Output
    $env:RP2C_REORG_OUTPUT = Join-Path $evidence 'reorg.json'
    & $upstream 'tests::rp2_authority_replay::g1_production_protocol_worker' '--exact' '--ignored' '--nocapture' *> $Log
    if ($LASTEXITCODE -ne 0) {
        throw "upstream worker $Mode failed; see $Log"
    }
}

Invoke-Upstream 'prepare-destination' (Join-Path $evidence 'prepare-destination.json') (Join-Path $evidence 'prepare-destination.log')
$env:D2_G1_MODE = 'import'
$env:D2_G1_STORAGE = $destinationStorage
$env:D2_G1_ARTIFACT = $artifactPath
$env:D2_G1_WORKER_RESULT = Join-Path $evidence 'd2-import.json'
& $d2 'upstream::tests::production_g1_external_worker' '--exact' '--ignored' '--nocapture' *> (Join-Path $evidence 'd2-import.log')
if ($LASTEXITCODE -ne 0) {
    throw 'production D2 reorg import failed; see evidence/d2-import.log'
}

Invoke-Upstream 'reorg' (Join-Path $evidence 'reorg.json') (Join-Path $evidence 'reorg.log')
Invoke-Upstream 'reorg-reopen' (Join-Path $evidence 'reorg-reopen.json') (Join-Path $evidence 'reorg-reopen.log')
$result = Get-Content -LiteralPath (Join-Path $evidence 'reorg-reopen.json') -Raw | ConvertFrom-Json
if (!$result.restart_coherent -or !$result.destination_owned_reorg -or $result.winning_branch_progress -ne 38) {
    throw 'production shallow reorg result failed final assertions'
}
Write-Output "production shallow reorg convergence passed; evidence: $evidence"
exit 0
