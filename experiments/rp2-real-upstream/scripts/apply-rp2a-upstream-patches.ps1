$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$Patch = Join-Path $ProjectRoot 'patches\rp2\0001-rp2a-observer-and-negative-controls.patch'

if (-not (Test-Path -LiteralPath $Upstream)) {
    throw "Pinned upstream checkout is missing: $Upstream"
}
if (-not (Test-Path -LiteralPath $Patch)) {
    throw "RP2-A upstream patch is missing: $Patch"
}

$Head = (git -C $Upstream rev-parse HEAD).Trim()
if ($Head -ne '12e29522ab7e078ada704d4ac04cbc0498009b7b') {
    throw "Unexpected upstream HEAD: $Head"
}

$Observer = Join-Path $Upstream 'light-client-lib\src\rp2_observer.rs'
if (-not (Test-Path -LiteralPath $Observer)) {
    git -C $Upstream apply --whitespace=nowarn -- $Patch
}

$PostHead = (git -C $Upstream rev-parse HEAD).Trim()
if ($PostHead -ne '12e29522ab7e078ada704d4ac04cbc0498009b7b') {
    throw "Patch changed upstream HEAD unexpectedly: $PostHead"
}

Write-Output "RP2-A upstream patch applied/verified at $PostHead"
