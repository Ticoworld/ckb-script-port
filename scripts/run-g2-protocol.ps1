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
    [string] $Root,

    [int] $HandoffHeight = 40,
    [int] $TransactionCount = 2,
    [int] $OutputsPerTransaction = 1
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$rootPath = [IO.Path]::GetFullPath($Root)
$projectPath = [IO.Path]::GetFullPath($repo)
if (!$rootPath.StartsWith($projectPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "G2 protocol root must be inside the project: $rootPath"
}
if (Test-Path -LiteralPath $rootPath) {
    throw "Refusing to reuse an existing G2 protocol root: $rootPath"
}
if ($HandoffHeight -lt 40 -or $TransactionCount -lt 1 -or $OutputsPerTransaction -lt 1) {
    throw 'G2 protocol parameters are outside the supported fixture bounds'
}
New-Item -ItemType Directory -Force -Path $rootPath | Out-Null

$sourceBackend = if ($Direction -eq 'rocks-to-sqlite') { 'rocksdb' } else { 'sqlite' }
$destinationBackend = if ($Direction -eq 'rocks-to-sqlite') { 'sqlite' } else { 'rocksdb' }
$sourceUpstream = (Resolve-Path -LiteralPath $UpstreamSourceExe).Path
$destinationUpstream = (Resolve-Path -LiteralPath $UpstreamDestinationExe).Path
$d2Source = (Resolve-Path -LiteralPath $D2SourceExe).Path
$d2Destination = (Resolve-Path -LiteralPath $D2DestinationExe).Path
$sourceStorage = Join-Path $rootPath 'source-storage'
$sourceChain = Join-Path $rootPath 'source-chain-db'
$destinationStorage = Join-Path $rootPath 'destination-storage'
$destinationChain = Join-Path $rootPath 'destination-chain-db'
$rescanStorage = Join-Path $rootPath 'rescan-storage'
$rescanChain = Join-Path $rootPath 'rescan-chain-db'
$evidence = Join-Path $rootPath 'evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null

$metadata = Join-Path $evidence 'metadata.json'
$artifact = Join-Path $evidence 'handoff.d2'
$postH = Join-Path $evidence 'post-h.json'

function Invoke-Upstream {
    param(
        [string] $Executable,
        [string] $Mode,
        [string] $Storage,
        [string] $Chain,
        [string] $Output,
        [string] $Log
    )
    $env:G2_MODE = $Mode
    $env:G2_WORKLOAD = 'REALISTIC-SYNTHETIC-PROTOCOL'
    $env:G2_STORAGE = $Storage
    $env:G2_CHAIN_DB = $Chain
    $env:G2_HANDOFF_HEIGHT = $HandoffHeight.ToString()
    $env:G2_TRANSACTION_COUNT = $TransactionCount.ToString()
    $env:G2_OUTPUTS_PER_TRANSACTION = $OutputsPerTransaction.ToString()
    $env:G2_METADATA = $metadata
    $env:G2_OUTPUT = $Output
    $env:G2_POST_H_OUTPUT = $postH
    & $Executable 'tests::rp2_authority_replay::g2_realism_worker' '--exact' '--ignored' '--nocapture' *> $Log
    if ($LASTEXITCODE -ne 0) { throw "upstream G2 worker $Mode failed; see $Log" }
}

function Invoke-D2 {
    param(
        [string] $Executable,
        [string] $Mode,
        [string] $Storage,
        [string] $Script,
        [string] $Result,
        [string] $Log
    )
    $env:D2_G2_MODE = $Mode
    $env:D2_G2_STORAGE = $Storage
    $env:D2_G2_ARTIFACT = $artifact
    $env:D2_G2_SCRIPT = $Script
    $env:D2_G2_RESULT = $Result
    & $Executable 'upstream::tests::production_g2_worker' '--exact' '--ignored' '--nocapture' *> $Log
    if ($LASTEXITCODE -ne 0) { throw "production G2 worker $Mode failed; see $Log" }
}

$sourcePreparation = Join-Path $evidence 'source-preparation.json'
Invoke-Upstream $sourceUpstream 'prepare-source' $sourceStorage $sourceChain $sourcePreparation (Join-Path $evidence 'source-preparation.log')
$scriptHex = (Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json).script_hex
$export = Join-Path $evidence 'export.json'
Invoke-D2 $d2Source 'export' $sourceStorage $scriptHex $export (Join-Path $evidence 'export.log')

$destinationPreparation = Join-Path $evidence 'destination-preparation.json'
Invoke-Upstream $destinationUpstream 'prepare-destination' $destinationStorage $destinationChain $destinationPreparation (Join-Path $evidence 'destination-preparation.log')
$import = Join-Path $evidence 'import.json'
Invoke-D2 $d2Destination 'import' $destinationStorage $scriptHex $import (Join-Path $evidence 'import.log')

$append = Join-Path $evidence 'append-post-h.json'
Invoke-Upstream $destinationUpstream 'append-post-h' $destinationStorage $destinationChain $append (Join-Path $evidence 'append-post-h.log')
$continuation = Join-Path $evidence 'continuation.json'
Invoke-Upstream $destinationUpstream 'continue' $destinationStorage $destinationChain $continuation (Join-Path $evidence 'continuation.log')

$rescanPreparation = Join-Path $evidence 'rescan-preparation.json'
Invoke-Upstream $destinationUpstream 'prepare-destination' $rescanStorage $rescanChain $rescanPreparation (Join-Path $evidence 'rescan-preparation.log')
$rescan = Join-Path $evidence 'rescan.json'
Invoke-Upstream $destinationUpstream 'rescan' $rescanStorage $rescanChain $rescan (Join-Path $evidence 'rescan.log')

$continuationJson = Get-Content -LiteralPath $continuation -Raw | ConvertFrom-Json
$rescanJson = Get-Content -LiteralPath $rescan -Raw | ConvertFrom-Json
$importJson = Get-Content -LiteralPath $import -Raw | ConvertFrom-Json
if (!$continuationJson.reopen_and_continue -or $continuationJson.script_progress -lt $continuationJson.post_h_transaction_height) {
    throw 'G2 protocol continuation assertions failed'
}
if ($continuationJson.request_starts | Where-Object { $_ -le $HandoffHeight }) {
    throw 'G2 protocol continuation requested historical range through H'
}
if ($importJson.idempotent -or $rescanJson.state.script_progress -ne $HandoffHeight) {
    throw 'G2 protocol import/rescan assertions failed'
}

$summary = [ordered]@{
    schema_version = 1
    experiment = 'D2-G2-pinned-protocol-realistic-synthetic'
    captured_local = (Get-Date).ToString('o')
    project_commit = (git -C $repo rev-parse HEAD).Trim()
    upstream_profile = 'ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1'
    direction = $Direction
    source_backend = $sourceBackend
    destination_backend = $destinationBackend
    handoff_height = $HandoffHeight
    transaction_count = $TransactionCount
    outputs_per_transaction = $OutputsPerTransaction
    production_export = Get-Content -LiteralPath $export -Raw | ConvertFrom-Json
    production_import = $importJson
    protocol_continuation = $continuationJson
    protocol_rescan = $rescanJson
    evidence = $evidence
}
$summary | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath (Join-Path $rootPath 'summary.json') -Encoding utf8
Write-Output "G2 pinned protocol evidence: $(Join-Path $rootPath 'summary.json')"
exit 0
