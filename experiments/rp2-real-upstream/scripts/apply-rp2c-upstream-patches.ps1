$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$PatchD = Join-Path $ProjectRoot 'patches\rp2\0004-rp2c-cross-backend-transport.patch'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'

if (-not (Test-Path -LiteralPath $Upstream)) {
    throw "Pinned upstream checkout is missing: $Upstream"
}
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) {
    throw "Unexpected upstream HEAD: $((git -C $Upstream rev-parse HEAD).Trim())"
}

# RP2-C is layered on the exact accepted RP2-A/RP2-B disposable worktree.
& (Join-Path $PSScriptRoot 'apply-rp2b-upstream-patches.ps1')
if (-not (Test-Path -LiteralPath $PatchD)) {
    throw "Required RP2-C patch is missing: $PatchD"
}

$SourceFile = Join-Path $Upstream 'light-client-lib\src\tests\rp2_authority_replay.rs'
if (-not (Select-String -LiteralPath $SourceFile -Pattern 'RP2C_ARTIFACT_VERSION' -Quiet)) {
    git -C $Upstream apply --whitespace=nowarn -- $PatchD
}

$PostHead = (git -C $Upstream rev-parse HEAD).Trim()
if ($PostHead -ne $Pinned) {
    throw "Applying RP2-C patch changed upstream HEAD unexpectedly: $PostHead"
}
if (-not (Select-String -LiteralPath $SourceFile -Pattern 'RP2C_ARTIFACT_VERSION' -Quiet)) {
    throw 'RP2-C transport sentinel is missing after patch application'
}
Write-Output "RP2-C upstream transport patch applied/verified at $PostHead"
