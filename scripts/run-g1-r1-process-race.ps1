param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('rocksdb', 'sqlite')]
    [string] $Backend,

    [Parameter(Mandatory = $true)]
    [string] $WorkerExe,

    [Parameter(Mandatory = $true)]
    [string] $Root,

    [int] $Count = 10
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
$worker = (Resolve-Path -LiteralPath $WorkerExe).Path
$rootPath = [IO.Path]::GetFullPath($Root)
New-Item -ItemType Directory -Force -Path $rootPath | Out-Null

function Start-D2Worker {
    param(
        [string] $Mode,
        [string] $Storage,
        [string] $Artifact,
        [string] $Result,
        [string] $Stdout,
        [string] $Stderr,
        [string] $PauseMarker,
        [string] $ReleaseMarker
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
    $info.Environment.Remove('D2_TEST_PAUSE_BEFORE_COMMIT')
    $info.Environment.Remove('D2_TEST_RELEASE_COMMIT')
    if ($PauseMarker) {
        $info.Environment['D2_TEST_PAUSE_BEFORE_COMMIT'] = $PauseMarker
        $info.Environment['D2_TEST_RELEASE_COMMIT'] = $ReleaseMarker
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $null = $process.Start()
    [PSCustomObject]@{
        Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
    }
}

function Finish-D2Worker {
    param(
        [PSCustomObject] $Worker,
        [string] $Stdout,
        [string] $Stderr
    )

    $Worker.Process.WaitForExit()
    [IO.File]::WriteAllText($Stdout, $Worker.Stdout.Result)
    [IO.File]::WriteAllText($Stderr, $Worker.Stderr.Result)
    [PSCustomObject]@{
        ExitCode = $Worker.Process.ExitCode
        Stdout = $Worker.Stdout.Result
        Stderr = $Worker.Stderr.Result
    }
}

function Read-WorkerJson {
    param([string] $Path)
    if (!(Test-Path -LiteralPath $Path)) {
        return $null
    }
    $text = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }
    try {
        return $text | ConvertFrom-Json
    } catch {
        return $null
    }
}

$summary = [System.Collections.Generic.List[object]]::new()
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
    if ($LASTEXITCODE -ne 0) {
        throw "race preparation failed for $Backend case $index"
    }

    $winnerResult = Join-Path $evidence 'winner.json'
    $winnerStdout = Join-Path $evidence 'winner.stdout'
    $winnerStderr = Join-Path $evidence 'winner.stderr'
    $contenderResult = Join-Path $evidence 'contender.json'
    $contenderStdout = Join-Path $evidence 'contender.stdout'
    $contenderStderr = Join-Path $evidence 'contender.stderr'
    $postResult = Join-Path $evidence 'post-race.json'
    $postStdout = Join-Path $evidence 'post-race.stdout'
    $postStderr = Join-Path $evidence 'post-race.stderr'
    $ready = Join-Path $evidence 'winner-ready'
    $release = Join-Path $evidence 'winner-release'

    $winner = Start-D2Worker 'race-import' $destination $artifact $winnerResult $winnerStdout $winnerStderr $ready $release
    $deadline = (Get-Date).AddSeconds(15)
    while (!(Test-Path -LiteralPath $ready) -and (Get-Date) -lt $deadline) {
        if ($winner.Process.HasExited) {
            break
        }
        Start-Sleep -Milliseconds 20
    }

    $contender = Start-D2Worker 'race-import' $destination $artifact $contenderResult $contenderStdout $contenderStderr $null $null
    Start-Sleep -Milliseconds 1000
    New-Item -ItemType File -Force -Path $release | Out-Null
    $winnerFinished = Finish-D2Worker $winner $winnerStdout $winnerStderr
    $contenderFinished = Finish-D2Worker $contender $contenderStdout $contenderStderr

    $post = Start-D2Worker 'race-import' $destination $artifact $postResult $postStdout $postStderr $null $null
    $postFinished = Finish-D2Worker $post $postStdout $postStderr

    $winnerJson = Read-WorkerJson $winnerResult
    $contenderJson = Read-WorkerJson $contenderResult
    $postJson = Read-WorkerJson $postResult
    $typedWinner = $winnerJson -and $winnerJson.outcome -eq 'accepted' -and !$winnerJson.idempotent
    $typedLoser = $contenderJson -and $contenderJson.outcome -eq 'rejected' -and $contenderJson.class -eq 'Retryable'
    $typedPost = $postJson -and $postJson.outcome -eq 'accepted' -and $postJson.idempotent
    $casePass = $winnerFinished.ExitCode -eq 0 -and $contenderFinished.ExitCode -eq 0 -and $postFinished.ExitCode -eq 0 -and $typedWinner -and $typedLoser -and $typedPost
    if (!$casePass) {
        $failed = $true
    }

    $record = [ordered]@{
        backend = $Backend
        repetition = $index
        phase = 'winner-paused-before-commit; contender-during-preparation; post-race-after-commit'
        winner_exit = $winnerFinished.ExitCode
        contender_exit = $contenderFinished.ExitCode
        post_race_exit = $postFinished.ExitCode
        winner = $winnerJson
        contender = $contenderJson
        post_race = $postJson
        pass = $casePass
        evidence = $evidence
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'race-result.json')
    $summary.Add([PSCustomObject]$record)
    Write-Output ("{0} case {1:D2}: pass={2} winner={3} contender={4} post={5}" -f $Backend, $index, $casePass, $winnerFinished.ExitCode, $contenderFinished.ExitCode, $postFinished.ExitCode)
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rootPath 'summary.json')
if ($failed) {
    exit 1
}
exit 0
