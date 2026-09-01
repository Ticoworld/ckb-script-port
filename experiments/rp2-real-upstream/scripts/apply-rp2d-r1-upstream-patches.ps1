$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw 'Unexpected pinned upstream HEAD' }

# RP2-D-R1 is layered on the accepted RP2-D source tree.  The first five
# patches remain immutable; this script applies only the new focused safety
# patch when the lifecycle sentinel is absent.
& (Join-Path $PSScriptRoot 'apply-rp2d-upstream-patches.ps1')
$Safety = Join-Path $ProjectRoot 'patches\rp2\0006-rp2d-exclusive-import-safety-seam.patch'
$Edge = Join-Path $ProjectRoot 'patches\rp2\0007-rp2d-commit-edge-observability.patch'
$Sentinel = Join-Path $Upstream 'light-client-lib\src\storage\mod.rs'
if (-not (Select-String -LiteralPath $Sentinel -Pattern 'ImportLifecycle' -Quiet)) {
    if (-not (Test-Path -LiteralPath $Safety)) { throw "Missing R1 safety patch: $Safety" }
    git -C $Upstream apply --whitespace=nowarn -- $Safety
}
if (-not (Select-String -LiteralPath $Sentinel -Pattern 'ImportLifecycle' -Quiet)) { throw 'R1 lifecycle sentinel missing' }
if (-not (Select-String -LiteralPath $Sentinel -Pattern 'RP2D_COMMIT_ARMED' -Quiet)) {
    if (-not (Test-Path -LiteralPath $Edge)) { throw "Missing R1 commit-edge patch: $Edge" }
    git -C $Upstream apply --whitespace=nowarn --ignore-space-change --ignore-whitespace -- $Edge
}
if (-not (Select-String -LiteralPath $Sentinel -Pattern 'RP2D_COMMIT_ARMED' -Quiet)) { throw 'R1 commit-edge sentinel missing' }
Write-Output "RP2-D-R1 safety seam applied/verified at $Pinned"
