param(
    [string]$SshKeyPath = "$HOME\.ssh\ssh-key-1787325222691",

    [string]$SenderSsh = "sender@89.169.186.8",
    [string]$ReceiverSsh = "receiver@89.169.182.89",

    [string]$SenderRepo = "/home/sender/projects/low-latency-data-transfer-challenge",
    [string]$ReceiverRepo = "/home/receiver/projects/low-latency-data-transfer-challenge",

    [string]$SenderManagementIp = "10.129.0.17",
    [string]$SenderDataIp = "10.131.0.4",
    [string]$ReceiverDataIp = "10.131.0.24",
    [string]$NextHopMac = "00:00:5e:00:01:00",

    [ValidateSet("raw", "compact")]
    [string]$Profile = "raw",

    [switch]$Batching,
    [switch]$SkipBuild,

    [ValidateSet("trade", "bbo", "book", "mixed")]
    [string]$MessageType = "mixed",

    [int]$Rate = 200000,
    [int]$Samples = 1000000,
    [int]$WarmupSeconds = 5,
    [int]$Slots = 1024,
    [int]$DataPort = 9000,
    [string]$ShmName = "/fanout_ring",

    [int]$GoLeadSeconds = 10,
    [string]$RemoteResultRoot = "/var/tmp/lldt-benchmark",
    [string]$OutputRoot = ".\results"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Rate -le 0) {
    throw "Rate must be > 0 for controlled benchmark runs."
}

if ($Samples -le 0) {
    throw "Samples must be > 0."
}

if (-not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf)) {
    throw "SSH key not found: $SshKeyPath"
}

$SshKeyPath = (Resolve-Path -LiteralPath $SshKeyPath).Path

$SshOptions = @(
    "-T",
    "-n",
    "-i", $SshKeyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=8",
    "-o", "ConnectionAttempts=1",
    "-o", "ServerAliveInterval=10",
    "-o", "ServerAliveCountMax=2"
)

$ScpOptions = @(
    "-i", $SshKeyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=8",
    "-o", "ConnectionAttempts=1"
)


# -----------------------------------------------------------------------------
# Native process wrapper.
#
# We intentionally do not invoke ssh.exe/scp.exe through PowerShell's "&"
# operator. In Windows PowerShell, stderr from a successful native command can
# be promoted to NativeCommandError when $ErrorActionPreference = "Stop".
#
# This wrapper uses the real Process.ExitCode and keeps stdout/stderr separate.
# -----------------------------------------------------------------------------

function Quote-NativeArgument {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')

    $slashes = 0

    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            ++$slashes
            continue
        }

        if ($ch -eq '"') {
            if ($slashes -gt 0) {
                [void]$builder.Append((('\' * ($slashes * 2)) -join ''))
            }

            [void]$builder.Append('\')
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }

        if ($slashes -gt 0) {
            [void]$builder.Append((('\' * $slashes) -join ''))
            $slashes = 0
        }

        [void]$builder.Append($ch)
    }

    # Backslashes immediately before the terminating quote must be doubled.
    if ($slashes -gt 0) {
        [void]$builder.Append((('\' * ($slashes * 2)) -join ''))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}


function Join-NativeArguments {
    param(
        [string[]]$Arguments
    )

    $parts = foreach ($arg in $Arguments) {
        Quote-NativeArgument $arg
    }

    return ($parts -join " ")
}


function Invoke-NativeCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 30
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = Join-NativeArguments $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw "Could not start $FilePath."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $finished = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $finished) {
            try {
                $process.Kill()
            }
            catch {
            }

            try {
                $process.WaitForExit()
            }
            catch {
            }

            $stdout = ""
            $stderr = ""

            try {
                $stdout = $stdoutTask.GetAwaiter().GetResult()
            }
            catch {
            }

            try {
                $stderr = $stderrTask.GetAwaiter().GetResult()
            }
            catch {
            }

            return [PSCustomObject]@{
                ExitCode = $null
                TimedOut = $true
                StdOut   = $stdout.Trim()
                StdErr   = $stderr.Trim()
            }
        }

        # Complete async stdout/stderr draining.
        $process.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode

        return [PSCustomObject]@{
            ExitCode = $exitCode
            TimedOut = $false
            StdOut   = $stdout.Trim()
            StdErr   = $stderr.Trim()
        }
    }
    finally {
        $process.Dispose()
    }
}


function Invoke-SshText {
    param(
        [string]$HostName,
        [string]$Command,
        [int]$Attempts = 3,
        [int]$TimeoutSeconds = 30
    )

    $last = $null

    for ($attempt = 1; $attempt -le $Attempts; ++$attempt) {
        $last = Invoke-NativeCapture `
            "ssh.exe" `
            ($SshOptions + @($HostName, $Command)) `
            $TimeoutSeconds

        if (-not $last.TimedOut -and $last.ExitCode -eq 0) {
            # stderr is diagnostic output only. A zero ssh.exe exit code is
            # authoritative, e.g. systemd-run may print "Running as unit..."
            # to stderr on a completely successful launch.
            return $last.StdOut
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds 2
        }
    }

    if ($last.TimedOut) {
        $reason = "local timeout after $TimeoutSeconds s"
    }
    else {
        $reason = "exit=$($last.ExitCode)"
    }

    $details = $reason

    if ($last.StdOut.Length -gt 0) {
        $details += "`nstdout:`n$($last.StdOut)"
    }

    if ($last.StdErr.Length -gt 0) {
        $details += "`nstderr:`n$($last.StdErr)"
    }

    throw "SSH command failed on $HostName after $Attempts attempt(s):`n$details"
}


function Copy-RemoteDirectory {
    param(
        [string]$HostName,
        [string]$RemotePath,
        [string]$LocalParent,
        [string]$ExpectedLocalDirectory,
        [int]$Attempts = 3,
        [int]$TimeoutSeconds = 120
    )

    $last = $null

    for ($attempt = 1; $attempt -le $Attempts; ++$attempt) {
        $last = Invoke-NativeCapture `
            "scp.exe" `
            ($ScpOptions + @("-r", "${HostName}:$RemotePath", $LocalParent)) `
            $TimeoutSeconds

        if (
            -not $last.TimedOut -and
            $last.ExitCode -eq 0 -and
            (Test-Path -LiteralPath $ExpectedLocalDirectory -PathType Container)
        ) {
            return
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds 2
        }
    }

    if ($last.TimedOut) {
        $reason = "local timeout after $TimeoutSeconds s"
    }
    else {
        $reason = "exit=$($last.ExitCode)"
    }

    $details = $reason

    if ($last.StdOut.Length -gt 0) {
        $details += "`nstdout:`n$($last.StdOut)"
    }

    if ($last.StdErr.Length -gt 0) {
        $details += "`nstderr:`n$($last.StdErr)"
    }

    throw "SCP failed for ${HostName}:$RemotePath`n$details"
}


function Get-RemoteStatus {
    param(
        [string]$HostName,
        [string]$RunDir
    )

    $text = Invoke-SshText `
        $HostName `
        "cat '$RunDir/status' 2>/dev/null || true"

    foreach ($line in ($text -split "`r?`n")) {
        $value = $line.Trim()

        if ($value -match '^(PREPARING|READY|RUNNING|DONE|FAILED(?:\s+[0-9]+)?)$') {
            return $value
        }
    }

    return ""
}


function Get-RemoteCommit {
    param(
        [string]$HostName,
        [string]$RunDir
    )

    $text = Invoke-SshText `
        $HostName `
        "cat '$RunDir/commit' 2>/dev/null || true"

    foreach ($line in ($text -split "`r?`n")) {
        $value = $line.Trim()

        if ($value -match '^[0-9a-fA-F]{40}$') {
            return $value.ToLowerInvariant()
        }
    }

    return ""
}


function Get-SenderEpoch {
    for ($attempt = 1; $attempt -le 10; ++$attempt) {
        try {
            $text = Invoke-SshText `
                $SenderSsh `
                "date +%s" `
                1 `
                15

            foreach ($line in ($text -split "`r?`n")) {
                $value = $line.Trim()

                if ($value -match '^[0-9]+$') {
                    return [Int64]$value
                }
            }
        }
        catch {
        }

        Start-Sleep -Seconds 1
    }

    throw "Could not read Sender clock."
}


function Set-RemoteGo {
    param(
        [string]$HostName,
        [string]$RunDir,
        [Int64]$GoEpoch
    )

    for ($attempt = 1; $attempt -le 10; ++$attempt) {
        try {
            $command =
                "printf '%s\n' '$GoEpoch' | " +
                "sudo -n tee '$RunDir/go' >/dev/null && " +
                "cat '$RunDir/go'"

            $text = Invoke-SshText `
                $HostName `
                $command `
                1 `
                15

            foreach ($line in ($text -split "`r?`n")) {
                if ($line.Trim() -eq "$GoEpoch") {
                    return
                }
            }
        }
        catch {
        }

        Start-Sleep -Seconds 1
    }

    throw "Could not deliver GO to $HostName."
}


function Wait-ForReady {
    param(
        [string]$SenderRunDir,
        [string]$ReceiverRunDir,
        [int]$TimeoutSeconds = 1200
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        try {
            $senderStatus = Get-RemoteStatus $SenderSsh $SenderRunDir
        }
        catch {
            $senderStatus = "SSH?"
        }

        try {
            $receiverStatus = Get-RemoteStatus $ReceiverSsh $ReceiverRunDir
        }
        catch {
            $receiverStatus = "SSH?"
        }

        Write-Host "Prepare: sender=$senderStatus receiver=$receiverStatus"

        if ($senderStatus.StartsWith("FAILED")) {
            throw "Sender benchmark node failed during preparation."
        }

        if ($receiverStatus.StartsWith("FAILED")) {
            throw "Receiver benchmark node failed during preparation."
        }

        if ($senderStatus -eq "READY" -and $receiverStatus -eq "READY") {
            return
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out waiting for benchmark nodes to become READY."
}


function Copy-RoleArtifacts {
    param(
        [string]$HostName,
        [string]$RemoteRoleDir,
        [string]$LocalRunDir,
        [string]$Role
    )

    $localRoleDir = Join-Path $LocalRunDir $Role

    if (Test-Path -LiteralPath $localRoleDir) {
        Remove-Item -LiteralPath $localRoleDir -Recurse -Force
    }

    Copy-RemoteDirectory `
        $HostName `
        $RemoteRoleDir `
        $LocalRunDir `
        $localRoleDir `
        3 `
        180

    if (-not (Test-Path -LiteralPath (Join-Path $localRoleDir "status") -PathType Leaf)) {
        throw "Collected $Role directory does not contain status file."
    }
}


$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$SenderRunDir = "$RemoteResultRoot/$RunId/sender"
$ReceiverRunDir = "$RemoteResultRoot/$RunId/receiver"

$LocalRunDir = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force $LocalRunDir | Out-Null

$ExpectedSeconds = [int][Math]::Ceiling([double]$Samples / [double]$Rate)
$MeasurementTimeout = [Math]::Max(15, $ExpectedSeconds * 3)
$BatchingValue = if ($Batching) { 1 } else { 0 }
$SkipBuildValue = if ($SkipBuild) { 1 } else { 0 }


function New-LaunchCommand {
    param(
        [string]$Repo,
        [string]$Role
    )

    return (
        "cd '$Repo' && " +
        "sudo -n ./scripts/launch_benchmark_node.sh " +
        "--role '$Role' " +
        "--run-id '$RunId' " +
        "--profile '$Profile' " +
        "--batching '$BatchingValue' " +
        "--rate '$Rate' " +
        "--samples '$Samples' " +
        "--message-type '$MessageType' " +
        "--warmup-seconds '$WarmupSeconds' " +
        "--slots '$Slots' " +
        "--data-port '$DataPort' " +
        "--shm '$ShmName' " +
        "--sender-data-ip '$SenderDataIp' " +
        "--receiver-data-ip '$ReceiverDataIp' " +
        "--next-hop-mac '$NextHopMac' " +
        "--sender-management-ip '$SenderManagementIp' " +
        "--measurement-timeout '$MeasurementTimeout' " +
        "--skip-build '$SkipBuildValue'"
    )
}


Write-Host "Run:                 $RunId"
Write-Host "Profile:             $Profile"
Write-Host "Batching:            $([bool]$Batching)"
Write-Host "Rate:                $Rate msg/s"
Write-Host "Samples:             $Samples"
Write-Host "Measurement timeout: $MeasurementTimeout s"
Write-Host


Write-Host "Launching Receiver benchmark node..."
[void](
    Invoke-SshText `
        $ReceiverSsh `
        (New-LaunchCommand $ReceiverRepo "receiver") `
        3 `
        20
)


Write-Host "Launching Sender benchmark node..."
[void](
    Invoke-SshText `
        $SenderSsh `
        (New-LaunchCommand $SenderRepo "sender") `
        3 `
        20
)


Write-Host "Waiting for local preparation/build on both VMs..."
Wait-ForReady $SenderRunDir $ReceiverRunDir


$SenderCommit = Get-RemoteCommit $SenderSsh $SenderRunDir
$ReceiverCommit = Get-RemoteCommit $ReceiverSsh $ReceiverRunDir

if ($SenderCommit.Length -eq 0 -or $ReceiverCommit.Length -eq 0) {
    throw "Could not read benchmark commit from both nodes."
}

if ($SenderCommit -ne $ReceiverCommit) {
    throw "Commit mismatch: sender=$SenderCommit receiver=$ReceiverCommit"
}

Write-Host "Commit: $SenderCommit"


$SenderEpoch = Get-SenderEpoch
$GoEpoch = $SenderEpoch + $GoLeadSeconds

Write-Host "GO epoch: $GoEpoch (Sender clock, +$GoLeadSeconds s)"


Set-RemoteGo $ReceiverSsh $ReceiverRunDir $GoEpoch
Set-RemoteGo $SenderSsh $SenderRunDir $GoEpoch


$Manifest = [ordered]@{
    run_id = $RunId
    commit = $SenderCommit
    go_epoch = $GoEpoch

    profile = $Profile
    batching = [bool]$Batching

    rate = $Rate
    samples = $Samples
    message_type = $MessageType
    warmup_seconds = $WarmupSeconds
    measurement_timeout_seconds = $MeasurementTimeout

    slots = $Slots
    data_port = $DataPort
    shm = $ShmName

    sender_ssh = $SenderSsh
    receiver_ssh = $ReceiverSsh

    sender_management_ip = $SenderManagementIp
    sender_data_ip = $SenderDataIp
    receiver_data_ip = $ReceiverDataIp
    next_hop_mac = $NextHopMac
}

$Manifest |
    ConvertTo-Json -Depth 4 |
    Set-Content (Join-Path $LocalRunDir "manifest.json")


$QuietSeconds =
    $GoLeadSeconds +
    $WarmupSeconds +
    $MeasurementTimeout +
    5

Write-Host
Write-Host "Benchmark is autonomous now."
Write-Host "No SSH activity for $QuietSeconds s..."
Start-Sleep -Seconds $QuietSeconds


$SenderStatus = ""
$ReceiverStatus = ""

for ($attempt = 1; $attempt -le 10; ++$attempt) {
    try {
        $SenderStatus = Get-RemoteStatus $SenderSsh $SenderRunDir
    }
    catch {
        $SenderStatus = "SSH?"
    }

    try {
        $ReceiverStatus = Get-RemoteStatus $ReceiverSsh $ReceiverRunDir
    }
    catch {
        $ReceiverStatus = "SSH?"
    }

    if (
        $SenderStatus -ne "RUNNING" -and
        $ReceiverStatus -ne "RUNNING" -and
        $SenderStatus -ne "SSH?" -and
        $ReceiverStatus -ne "SSH?"
    ) {
        break
    }

    Start-Sleep -Seconds 2
}

Write-Host "Final status: sender=$SenderStatus receiver=$ReceiverStatus"


Write-Host "Collecting artifacts..."
Copy-RoleArtifacts $SenderSsh $SenderRunDir $LocalRunDir "sender"
Copy-RoleArtifacts $ReceiverSsh $ReceiverRunDir $LocalRunDir "receiver"


$LocalSenderStatus =
    (Get-Content (Join-Path $LocalRunDir "sender\status") -Raw).Trim()

$LocalReceiverStatus =
    (Get-Content (Join-Path $LocalRunDir "receiver\status") -Raw).Trim()


if ($LocalSenderStatus -ne "DONE" -or $LocalReceiverStatus -ne "DONE") {
    throw (
        "Benchmark failed. " +
        "sender=$LocalSenderStatus receiver=$LocalReceiverStatus. " +
        "Artifacts: $LocalRunDir"
    )
}


$LatencyCsv =
    Join-Path $LocalRunDir "receiver\latency.csv"

if (-not (Test-Path -LiteralPath $LatencyCsv -PathType Leaf)) {
    throw "Benchmark completed without latency.csv: $LocalRunDir"
}


Write-Host
Write-Host "Benchmark completed successfully:"
Write-Host "  $LocalRunDir"
