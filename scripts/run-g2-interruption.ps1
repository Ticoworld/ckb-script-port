param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('rocksdb', 'sqlite')]
    [string] $Backend,

    [Parameter(Mandatory = $true)]
    [string] $WorkerExe,

    [Parameter(Mandatory = $true)]
    [string] $Root,

    [ValidateRange(1, 10)]
    [int] $Count = 3
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$worker = (Resolve-Path -LiteralPath $WorkerExe).Path
$rootPath = [IO.Path]::GetFullPath($Root)
$projectPath = [IO.Path]::GetFullPath($repo)
if (!$rootPath.StartsWith($projectPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "G2 interruption root must be inside the project: $rootPath"
}
if (Test-Path -LiteralPath $rootPath) {
    throw "Refusing to reuse an existing G2 interruption root: $rootPath"
}
New-Item -ItemType Directory -Force -Path $rootPath | Out-Null

function Start-Worker {
    param(
        [string] $Mode,
        [string] $Storage,
        [string] $Artifact,
        [string] $Result,
        [string] $PauseMarker,
        [string] $ReleaseMarker,
        [string] $Stdout,
        [string] $Stderr
    )

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $worker
    $info.Arguments = 'upstream::tests::production_g1_external_worker --exact --ignored --nocapture'
    $info.WorkingDirectory = $repo
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['D2_G1_MODE'] = $Mode
    $info.Environment['D2_G1_STORAGE'] = $Storage
    $info.Environment['D2_G1_ARTIFACT'] = $Artifact
    $info.Environment['D2_G1_WORKER_RESULT'] = $Result
    if ($PauseMarker) {
        $info.Environment['D2_TEST_PAUSE_BEFORE_COMMIT'] = $PauseMarker
        $info.Environment['D2_TEST_RELEASE_COMMIT'] = $ReleaseMarker
    } else {
        $info.Environment.Remove('D2_TEST_PAUSE_BEFORE_COMMIT')
        $info.Environment.Remove('D2_TEST_RELEASE_COMMIT')
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (!$process.Start()) {
        throw "Unable to start G2 interruption worker: $Mode"
    }
    [PSCustomObject]@{
        Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
        StdoutPath = $Stdout
        StderrPath = $Stderr
    }
}

function Finish-Worker {
    param([PSCustomObject] $Worker)
    $Worker.Process.WaitForExit()
    $stdout = $Worker.Stdout.Result
    $stderr = $Worker.Stderr.Result
    [IO.File]::WriteAllText($Worker.StdoutPath, $stdout)
    [IO.File]::WriteAllText($Worker.StderrPath, $stderr)
    [PSCustomObject]@{
        ExitCode = $Worker.Process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Read-JsonOrNull {
    param([string] $Path)
    if (!(Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

$records = [System.Collections.Generic.List[object]]::new()
$failed = $false
for ($index = 1; $index -le $Count; $index++) {
    $case = Join-Path $rootPath ("case-{0:D2}" -f $index)
    $source = Join-Path $case 'source'
    $destination = Join-Path $case 'destination'
    $evidence = Join-Path $case 'evidence'
    New-Item -ItemType Directory -Force -Path $source, $destination, $evidence | Out-Null
    $artifact = Join-Path $evidence 'handoff.d2'
    $prepareResult = Join-Path $evidence 'prepare.json'
    $env:D2_G1_MODE = 'race-prepare'
    $env:D2_G1_SOURCE = $source
    $env:D2_G1_STORAGE = $destination
    $env:D2_G1_ARTIFACT = $artifact
    $env:D2_G1_WORKER_RESULT = $prepareResult
    & $worker 'upstream::tests::production_g1_external_worker' '--exact' '--ignored' '--nocapture' *> (Join-Path $evidence 'prepare.stdout')
    if ($LASTEXITCODE -ne 0) { throw "G2 interruption preparation failed for case $index" }

    $ready = Join-Path $evidence 'prepared-before-commit'
    $release = Join-Path $evidence 'never-released'
    $killedResult = Join-Path $evidence 'killed.json'
    $killed = Start-Worker 'race-import' $destination $artifact $killedResult $ready $release `
        (Join-Path $evidence 'killed.stdout') (Join-Path $evidence 'killed.stderr')
    $deadline = (Get-Date).AddSeconds(15)
    while (!(Test-Path -LiteralPath $ready) -and !$killed.Process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 20
    }
    if (!(Test-Path -LiteralPath $ready)) {
        if (!$killed.Process.HasExited) { Stop-Process -Id $killed.Process.Id -Force }
        throw "G2 interruption worker did not reach pre-commit marker in case $index"
    }
    Stop-Process -Id $killed.Process.Id -Force
    $killed.Process.WaitForExit()
    $killedStdout = $killed.Stdout.Result
    $killedStderr = $killed.Stderr.Result
    [IO.File]::WriteAllText((Join-Path $evidence 'killed.stdout'), $killedStdout)
    [IO.File]::WriteAllText((Join-Path $evidence 'killed.stderr'), $killedStderr)

    $retryResult = Join-Path $evidence 'retry.json'
    $retry = Start-Worker 'race-import' $destination $artifact $retryResult $null $null `
        (Join-Path $evidence 'retry.stdout') (Join-Path $evidence 'retry.stderr')
    $retryFinished = Finish-Worker $retry
    $reopenResult = Join-Path $evidence 'reopen-retry.json'
    $reopen = Start-Worker 'race-import' $destination $artifact $reopenResult $null $null `
        (Join-Path $evidence 'reopen.stdout') (Join-Path $evidence 'reopen.stderr')
    $reopenFinished = Finish-Worker $reopen
    $retryJson = Read-JsonOrNull $retryResult
    $reopenJson = Read-JsonOrNull $reopenResult
    $casePass = $retryFinished.ExitCode -eq 0 -and $reopenFinished.ExitCode -eq 0 -and
        $retryJson.outcome -eq 'accepted' -and !$retryJson.idempotent -and
        $reopenJson.outcome -eq 'accepted' -and $reopenJson.idempotent
    if (!$casePass) { $failed = $true }
    $record = [ordered]@{
        backend = $Backend
        repetition = $index
        interruption = 'controlled process termination after validation/preparation and before native commit'
        killed_exit = $killed.Process.ExitCode
        retry_exit = $retryFinished.ExitCode
        reopen_exit = $reopenFinished.ExitCode
        retry = $retryJson
        reopen_retry = $reopenJson
        pass = $casePass
        evidence = $evidence
    }
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'result.json')
    $records.Add([PSCustomObject]$record)
    Write-Output ("{0} case {1:D2}: pass={2} killed={3} retry={4} reopen={5}" -f $Backend, $index, $casePass, $killed.Process.ExitCode, $retryFinished.ExitCode, $reopenFinished.ExitCode)
}

$records | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $rootPath 'summary.json')
if ($failed) { exit 1 }
exit 0
