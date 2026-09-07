$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$workRoot = Join-Path $projectRoot "_work\g1-cross-backend"
New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

if (Test-Path (Join-Path $projectRoot "_work\libclang\package\runtimes\win-x64\native")) {
    $env:LIBCLANG_PATH = (Resolve-Path (Join-Path $projectRoot "_work\libclang\package\runtimes\win-x64\native")).Path
    $env:CXXFLAGS = "-D_WIN32_WINNT=0x0602"
}

function Invoke-Exchange([string[]] $cargoArgs, [string] $artifactPath) {
    $env:D2_G1_EXCHANGE_ARTIFACT = $artifactPath
    $env:D2_G1_EXCHANGE_MODE = "export"
    & cargo test -p d2-script-handoff --offline --lib upstream::tests::production_adapter_cross_backend_exchange @cargoArgs -- --exact --ignored
    if ($LASTEXITCODE -ne 0) { throw "export test failed for $artifactPath" }

    $env:D2_G1_EXCHANGE_MODE = "import"
    & cargo test -p d2-script-handoff --offline --lib upstream::tests::production_adapter_cross_backend_exchange @cargoArgs -- --exact --ignored
    if ($LASTEXITCODE -ne 0) { throw "import test failed for $artifactPath" }
}

Push-Location $projectRoot
try {
    $rocksToSqlite = Join-Path $workRoot "rocks-to-sqlite.d2"
    Invoke-Exchange @() $rocksToSqlite

    $sqliteToRocks = Join-Path $workRoot "sqlite-to-rocks.d2"
    Invoke-Exchange @("--no-default-features", "--features", "sqlite") $sqliteToRocks

    Write-Output "G1 cross-backend production exchange passed in both directions."
}
finally {
    Pop-Location
}
