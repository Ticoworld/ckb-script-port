param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('rocks-to-sqlite', 'sqlite-to-rocks')]
    [string] $Direction,

    [Parameter(Mandatory = $true)]
    [string] $UpstreamSourceExe,

    [Parameter(Mandatory = $true)]
    [string] $UpstreamDestinationExe,

    [Parameter(Mandatory = $true)]
    [string] $D2SourceExe,

    [Parameter(Mandatory = $true)]
    [string] $D2DestinationExe,

    [Parameter(Mandatory = $true)]
    [string] $Root
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$rootPath = [IO.Path]::GetFullPath($Root)
$sourceUpstream = (Resolve-Path -LiteralPath $UpstreamSourceExe).Path
$destinationUpstream = (Resolve-Path -LiteralPath $UpstreamDestinationExe).Path
$d2Source = (Resolve-Path -LiteralPath $D2SourceExe).Path
$d2Destination = (Resolve-Path -LiteralPath $D2DestinationExe).Path
New-Item -ItemType Directory -Force -Path $rootPath | Out-Null
$sourceStorage = Join-Path $rootPath 'source-storage'
$sourceChainDb = Join-Path $rootPath 'source-chain-db'
$destinationStorage = Join-Path $rootPath 'destination-storage'
$destinationChainDb = Join-Path $rootPath 'destination-chain-db'
$controlStorage = Join-Path $rootPath 'control-storage'
$controlChainDb = Join-Path $rootPath 'control-chain-db'
$evidence = Join-Path $rootPath 'evidence'
New-Item -ItemType Directory -Force -Path $sourceStorage, $sourceChainDb, $destinationStorage, $destinationChainDb, $controlStorage, $controlChainDb, $evidence | Out-Null

function Invoke-UpstreamWorker {
    param(
        [string] $Executable,
        [string] $Mode,
        [string] $Storage,
        [string] $ChainDb,
        [string] $Metadata,
        [string] $Output,
        [string] $Log
    )
    $env:RP2C_MODE = $Mode
    $env:RP2C_CASE = "g1-r1-$Direction"
    $env:RP2C_SOURCE_STORAGE = $sourceStorage
    $env:RP2C_SOURCE_CHAIN_DB = $sourceChainDb
    $env:RP2C_DESTINATION_STORAGE = $Storage
    $env:RP2C_DESTINATION_CHAIN_DB = $ChainDb
    $env:RP2C_CONTROL_STORAGE = $controlStorage
    $env:RP2C_CONTROL_CHAIN_DB = $controlChainDb
    $env:RP2C_METADATA = $Metadata
    $env:RP2C_OUTPUT = $Output
    $env:RP2C_REORG_OUTPUT = (Join-Path $evidence 'reorg.json')
    & $Executable 'tests::rp2_authority_replay::g1_production_protocol_worker' '--exact' '--ignored' '--nocapture' *> $Log
    if ($LASTEXITCODE -ne 0) {
        throw "upstream worker $Mode failed for $Direction; see $Log"
    }
}

function Invoke-D2Worker {
    param(
        [string] $Executable,
        [string] $Mode,
        [string] $Storage,
        [string] $Artifact,
        [string] $Script,
        [string] $Result,
        [string] $Log
    )
    $env:D2_G1_MODE = $Mode
    $env:D2_G1_STORAGE = $Storage
    $env:D2_G1_ARTIFACT = $Artifact
    $env:D2_G1_SCRIPT = $Script
    $env:D2_G1_WORKER_RESULT = $Result
    & $Executable 'upstream::tests::production_g1_external_worker' '--exact' '--ignored' '--nocapture' *> $Log
    if ($LASTEXITCODE -ne 0) {
        throw "D2 worker $Mode failed for $Direction; see $Log"
    }
}

$metadata = Join-Path $evidence 'metadata.json'
$sourcePreparation = Join-Path $evidence 'source-preparation.json'
Invoke-UpstreamWorker $sourceUpstream 'prepare-source' $sourceStorage $sourceChainDb $metadata $sourcePreparation (Join-Path $evidence 'source-preparation.log')
$scriptHex = (Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json).script_hex

$artifact = Join-Path $evidence 'handoff.d2'
$exportResult = Join-Path $evidence 'd2-export.json'
Invoke-D2Worker $d2Source 'export' $sourceStorage $artifact $scriptHex $exportResult (Join-Path $evidence 'd2-export.log')

$destinationPreparation = Join-Path $evidence 'destination-preparation.json'
Invoke-UpstreamWorker $destinationUpstream 'prepare-destination' $destinationStorage $destinationChainDb $metadata $destinationPreparation (Join-Path $evidence 'destination-preparation.log')
$controlPreparation = Join-Path $evidence 'control-preparation.json'
Invoke-UpstreamWorker $destinationUpstream 'prepare-destination' $controlStorage $controlChainDb $metadata $controlPreparation (Join-Path $evidence 'control-preparation.log')

$importResult = Join-Path $evidence 'd2-import.json'
Invoke-D2Worker $d2Destination 'import' $destinationStorage $artifact $scriptHex $importResult (Join-Path $evidence 'd2-import.log')

$continuation = Join-Path $evidence 'continuation.json'
Invoke-UpstreamWorker $destinationUpstream 'continuation' $destinationStorage $destinationChainDb $metadata $continuation (Join-Path $evidence 'continuation.log')
$continuationJson = Get-Content -LiteralPath $continuation -Raw | ConvertFrom-Json
if (!$continuationJson.positive_no_refilter_through_h -or !$continuationJson.negative_control_detected_historical_filtering) {
    throw "protocol continuation instrumentation did not pass both positive and negative controls"
}

Write-Output "$Direction production protocol continuation passed; evidence: $evidence"
Write-Output ("H={0}; post-H height={1}; positive starts={2}; negative starts={3}" -f $continuationJson.handoff_height, $continuationJson.post_h_transaction_height, ($continuationJson.positive_filter_request_starts -join ','), ($continuationJson.negative_control_filter_request_starts -join ','))
exit 0
