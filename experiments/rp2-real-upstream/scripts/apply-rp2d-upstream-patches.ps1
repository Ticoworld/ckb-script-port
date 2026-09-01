$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$Patch = Join-Path $ProjectRoot 'patches\rp2\0005-rp2d-reorg-crash-test.patch'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'

if (-not (Test-Path -LiteralPath $Upstream)) { throw "Pinned upstream checkout is missing: $Upstream" }
if (-not (Test-Path -LiteralPath $Patch)) { throw "Required RP2-D patch is missing: $Patch" }
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw "Unexpected upstream HEAD" }

& (Join-Path $PSScriptRoot 'apply-rp2c-upstream-patches.ps1')
$Source = Join-Path $Upstream 'light-client-lib\src\tests\rp2_authority_replay.rs'
if (-not (Select-String -LiteralPath $Source -Pattern 'rp2d_reorg_worker' -Quiet)) {
    git -C $Upstream apply --whitespace=nowarn -- $Patch
}
if (-not (Select-String -LiteralPath $Source -Pattern 'rp2d_reorg_worker' -Quiet)) {
    throw 'RP2-D worker sentinel is missing after patch application'
}
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw 'RP2-D patch changed upstream HEAD' }
Write-Output "RP2-D upstream reorg/crash patch applied/verified at $Pinned"
