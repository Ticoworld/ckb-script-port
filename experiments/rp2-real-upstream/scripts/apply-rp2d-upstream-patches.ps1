$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$Patch = Join-Path $ProjectRoot 'patches\rp2\0005-rp2d-reorg-crash-test.patch'
$LayeredFallback = Join-Path $ProjectRoot 'patches\rp2\0006-rp2d-exclusive-import-safety-seam.patch'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'

if (-not (Test-Path -LiteralPath $Upstream)) { throw "Pinned upstream checkout is missing: $Upstream" }
if (-not (Test-Path -LiteralPath $Patch)) { throw "Required RP2-D patch is missing: $Patch" }
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw "Unexpected upstream HEAD" }

& (Join-Path $PSScriptRoot 'apply-rp2c-upstream-patches.ps1')
$Source = Join-Path $Upstream 'light-client-lib\src\tests\rp2_authority_replay.rs'
if (-not (Select-String -LiteralPath $Source -Pattern 'rp2d_reorg_worker' -Quiet)) {
    # 0005 was preserved byte-for-byte, but its historical context overlaps
    # the accepted 0004 fixture additions.  Prefer it when it applies cleanly;
    # otherwise use the reviewable 0006 layered snapshot, which contains the
    # same RP2-D additions plus the R1 lifecycle seam and is based directly on
    # the post-0004 tree.  Neither path changes upstream HEAD.
    git -C $Upstream apply --check --whitespace=nowarn --ignore-space-change --ignore-whitespace -- $Patch
    if ($LASTEXITCODE -eq 0) {
        git -C $Upstream apply --whitespace=nowarn -- $Patch
    } else {
        if (-not (Test-Path -LiteralPath $LayeredFallback)) { throw "Missing layered RP2-D fallback: $LayeredFallback" }
        git -C $Upstream apply --whitespace=nowarn --ignore-space-change --ignore-whitespace -- $LayeredFallback
    }
}
if (-not (Select-String -LiteralPath $Source -Pattern 'rp2d_reorg_worker' -Quiet)) {
    throw 'RP2-D worker sentinel is missing after patch application'
}
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) { throw 'RP2-D patch changed upstream HEAD' }
Write-Output "RP2-D upstream reorg/crash patch applied/verified at $Pinned"
