$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Upstream = Join-Path $ProjectRoot '_work\upstream\ckb-light-client'
$PatchA = Join-Path $ProjectRoot 'patches\rp2\0001-rp2a-observer-and-negative-controls.patch'
$PatchB = Join-Path $ProjectRoot 'patches\rp2\0002-rp2b-typed-script-handoff.patch'
$PatchC = Join-Path $ProjectRoot 'patches\rp2\0003-rp2b-spendable-fixture.patch'
$Pinned = '12e29522ab7e078ada704d4ac04cbc0498009b7b'

if (-not (Test-Path -LiteralPath $Upstream)) {
    throw "Pinned upstream checkout is missing: $Upstream"
}
foreach ($Patch in @($PatchA, $PatchB, $PatchC)) {
    if (-not (Test-Path -LiteralPath $Patch)) {
        throw "Required RP2 patch is missing: $Patch"
    }
}
if ((git -C $Upstream rev-parse HEAD).Trim() -ne $Pinned) {
    throw "Unexpected upstream HEAD: $((git -C $Upstream rev-parse HEAD).Trim())"
}

# The disposable checkout is intentionally left patched between runs.  Apply
# each patch only when its sentinel file is absent so the script is idempotent.
if (-not (Test-Path -LiteralPath (Join-Path $Upstream 'light-client-lib\src\rp2_observer.rs'))) {
    git -C $Upstream apply --whitespace=nowarn -- $PatchA
}
if (-not (Test-Path -LiteralPath (Join-Path $Upstream 'light-client-lib\src\rp2_handoff.rs'))) {
    git -C $Upstream apply --whitespace=nowarn -- $PatchB
}
if (-not (Select-String -LiteralPath (Join-Path $Upstream 'light-client-lib\src\tests\utils\chain.rs') -Pattern 'new_with_spendable_pow' -Quiet)) {
    git -C $Upstream apply --whitespace=nowarn -- $PatchC
}

$PostHead = (git -C $Upstream rev-parse HEAD).Trim()
if ($PostHead -ne $Pinned) {
    throw "Applying RP2 patches changed upstream HEAD unexpectedly: $PostHead"
}
Write-Output "RP2-A and RP2-B upstream patches applied/verified at $PostHead"
