param(
    [string]$SshKeyPath =
        "$HOME\.ssh\ssh-key-1787325222691",

    [string]$SenderSshUser = "sender",
    [string]$SenderPublicIp = "89.169.186.8",

    [string]$ReceiverSshUser = "receiver",
    [string]$ReceiverPublicIp = "89.169.182.89",

    [string]$SenderRepo =
        "/home/sender/projects/low-latency-data-transfer-challenge",

    [string]$ReceiverRepo =
        "/home/receiver/projects/low-latency-data-transfer-challenge",

    [string]$SenderManagementIp = "10.129.0.17",
    [string]$ReceiverManagementIp = "10.129.0.18",

    [string]$SenderDataIp = "10.131.0.4",
    [string]$ReceiverDataIp = "10.131.0.24",

    [string]$NextHopMac = "00:00:5e:00:01:00",

    [string]$ShmName = "/fanout_ring",

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

    [string]$OutputRoot = ".\results"
)


Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


# -----------------------------------------------------------------------------
# SSH configuration.
# -----------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf)) {
    throw "SSH private key not found: $SshKeyPath"
}

$SshKeyPath =
    (Resolve-Path -LiteralPath $SshKeyPath).Path

$SenderSsh =
    "${SenderSshUser}@${SenderPublicIp}"

$ReceiverSsh =
    "${ReceiverSshUser}@${ReceiverPublicIp}"


$SshOptions = @(
    "-i", $SshKeyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=8",
    "-o", "ConnectionAttempts=1",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=2"
)

$ScpOptions = @(
    "-i", $SshKeyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=8",
    "-o", "ConnectionAttempts=1",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=2"
)


# -----------------------------------------------------------------------------
# Native process execution.
#
# Do not use:
#
#   & ssh.exe ...
#   $LASTEXITCODE
#
# The benchmark launcher needs the actual Process.ExitCode and a hard local
# timeout independent of OpenSSH's own timeout behaviour.
# -----------------------------------------------------------------------------

function ConvertTo-NativeArgument {
    param(
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($null -eq $Argument) {
        return '""'
    }

    if (
        $Argument.Length -gt 0 -and
        $Argument -notmatch '[\s"]'
    ) {
        return $Argument
    }

    $builder =
        [System.Text.StringBuilder]::new()

    [void]$builder.Append('"')

    $backslashes = 0

    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq [char]'\') {
            ++$backslashes
            continue
        }

        if ($ch -eq [char]'"') {
            if ($backslashes -gt 0) {
                [void]$builder.Append(
                    [char]'\',
                    $backslashes * 2
                )
            }

            [void]$builder.Append('\')
            [void]$builder.Append('"')

            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append(
                [char]'\',
                $backslashes
            )

            $backslashes = 0
        }

        [void]$builder.Append($ch)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append(
            [char]'\',
            $backslashes * 2
        )
    }

    [void]$builder.Append('"')

    return $builder.ToString()
}


function Join-NativeArguments {
    param(
        [string[]]$Arguments
    )

    $quoted = foreach ($argument in $Arguments) {
        ConvertTo-NativeArgument $argument
    }

    return ($quoted -join " ")
}


function Invoke-NativeCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds
    )

    $startInfo =
        [System.Diagnostics.ProcessStartInfo]::new()

    $startInfo.FileName =
        $FilePath

    $startInfo.Arguments =
        Join-NativeArguments $Arguments

    $startInfo.UseShellExecute =
        $false

    $startInfo.CreateNoWindow =
        $true

    $startInfo.RedirectStandardOutput =
        $true

    $startInfo.RedirectStandardError =
        $true


    $process =
        [System.Diagnostics.Process]::new()

    $process.StartInfo =
        $startInfo


    try {
        if (-not $process.Start()) {
            throw "Could not start $FilePath."
        }


        # Start asynchronous reads immediately so stdout/stderr pipe buffers
        # cannot deadlock the child process.
        $stdoutTask =
            $process.StandardOutput.ReadToEndAsync()

        $stderrTask =
            $process.StandardError.ReadToEndAsync()


        $finished =
            $process.WaitForExit(
                $TimeoutSeconds * 1000
            )


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
                $stdout =
                    $stdoutTask.GetAwaiter().GetResult()
            }
            catch {
            }

            try {
                $stderr =
                    $stderrTask.GetAwaiter().GetResult()
            }
            catch {
            }


            return [PSCustomObject]@{
                ExitCode = $null
                TimedOut = $true
                StdOut   = $stdout.TrimEnd()
                StdErr   = $stderr.TrimEnd()
            }
        }


        # Required when asynchronous output reads are used.
        $process.WaitForExit()


        $stdout =
            $stdoutTask.GetAwaiter().GetResult()

        $stderr =
            $stderrTask.GetAwaiter().GetResult()

        $exitCode =
            $process.ExitCode


        return [PSCustomObject]@{
            ExitCode = $exitCode
            TimedOut = $false
            StdOut   = $stdout.TrimEnd()
            StdErr   = $stderr.TrimEnd()
        }
    }
    finally {
        $process.Dispose()
    }
}


# -----------------------------------------------------------------------------
# SSH helpers.
# -----------------------------------------------------------------------------

function Invoke-SshCapture {
    param(
        [string]$HostName,
        [string]$Command,

        [int]$Attempts = 3,
        [int]$RetryDelaySeconds = 2,

        [int]$TimeoutSeconds = 30
    )

    $lastResult = $null


    for ($attempt = 1; $attempt -le $Attempts; ++$attempt) {
        $arguments =
            $SshOptions +
            @(
                $HostName,
                $Command
            )


        $result =
            Invoke-NativeCapture `
                "ssh.exe" `
                $arguments `
                $TimeoutSeconds


        $lastResult =
            $result


        if (
            -not $result.TimedOut -and
            $result.ExitCode -eq 0
        ) {
            return $result.StdOut
        }


        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }


    $details = ""

    if ($null -ne $lastResult) {
        if ($lastResult.TimedOut) {
            $details +=
                "local timeout after ${TimeoutSeconds}s"
        }
        else {
            $details +=
                "exit=$($lastResult.ExitCode)"
        }

        if ($lastResult.StdOut.Length -gt 0) {
            $details +=
                "`nstdout:`n$($lastResult.StdOut)"
        }

        if ($lastResult.StdErr.Length -gt 0) {
            $details +=
                "`nstderr:`n$($lastResult.StdErr)"
        }
    }


    throw (
        "SSH command failed on ${HostName} " +
        "after ${Attempts} attempt(s):`n" +
        $details
    )
}


function Copy-RemoteFile {
    param(
        [string]$HostName,
        [string]$RemotePath,
        [string]$LocalPath,

        [int]$Attempts = 3,
        [int]$TimeoutSeconds = 120
    )

    $lastResult = $null


    for ($attempt = 1; $attempt -le $Attempts; ++$attempt) {
        $arguments =
            $ScpOptions +
            @(
                "${HostName}:$RemotePath",
                $LocalPath
            )


        $result =
            Invoke-NativeCapture `
                "scp.exe" `
                $arguments `
                $TimeoutSeconds


        $lastResult =
            $result


        if (
            -not $result.TimedOut -and
            $result.ExitCode -eq 0
        ) {
            return
        }


        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds 2
        }
    }


    $details = ""

    if ($null -ne $lastResult) {
        if ($lastResult.TimedOut) {
            $details =
                "local timeout after ${TimeoutSeconds}s"
        }
        else {
            $details =
                "exit=$($lastResult.ExitCode)"
        }

        if ($lastResult.StdErr.Length -gt 0) {
            $details +=
                "`nstderr:`n$($lastResult.StdErr)"
        }
    }


    throw (
        "SCP failed: ${HostName}:$RemotePath`n" +
        $details
    )
}


# -----------------------------------------------------------------------------
# Detached remote-process helpers.
#
# Every process receives:
#
#   <name>.runner.sh
#   <name>.pid
#   <name>.exit
#   <name>.log
#
# The runner is detached from SSH by nohup + setsid.
# -----------------------------------------------------------------------------

function Start-RemoteProcess {
    param(
        [string]$HostName,
        [string]$Repo,
        [string]$RunDir,
        [string]$Name,
        [string]$Command
    )

    $PidPath =
        "$RunDir/$Name.pid"

    $ExitPath =
        "$RunDir/$Name.exit"

    $RunnerPath =
        "$RunDir/$Name.runner.sh"

    $LogPath =
        "$RunDir/$Name.log"


    $runnerTemplate = @'
#!/usr/bin/env bash
set +e

PID_FILE='__PID_FILE__'
EXIT_FILE='__EXIT_FILE__'

printf '%s\n' "$$" > "${PID_FILE}.tmp"
mv -f "${PID_FILE}.tmp" "${PID_FILE}"

cd '__REPO__'

if [[ $? -ne 0 ]]; then
    printf '%s\n' "200" > "${EXIT_FILE}.tmp"
    mv -f "${EXIT_FILE}.tmp" "${EXIT_FILE}"
    exit 200
fi

__COMMAND__

rc=$?

printf '%s\n' "${rc}" > "${EXIT_FILE}.tmp"
mv -f "${EXIT_FILE}.tmp" "${EXIT_FILE}"

exit "${rc}"
'@


    $runner =
        $runnerTemplate.
            Replace("__PID_FILE__", $PidPath).
            Replace("__EXIT_FILE__", $ExitPath).
            Replace("__REPO__", $Repo).
            Replace("__COMMAND__", $Command)


    $payload =
        [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($runner)
        )


    # Start is retry-safe enough:
    #
    # - an already alive process is accepted;
    # - an already completed process is not started again.
    $remote =
        "mkdir -p '$RunDir'; " +
        "if [ -f '$ExitPath' ]; then exit 2; fi; " +
        "if [ -s '$PidPath' ] && " +
        "sudo -n kill -0 -- -`$(cat '$PidPath') 2>/dev/null; " +
        "then exit 0; fi; " +
        "rm -f '$PidPath'; " +
        "printf '%s' '$payload' | base64 -d > '$RunnerPath'; " +
        "chmod 700 '$RunnerPath'; " +
        "nohup setsid '$RunnerPath' " +
        "> '$LogPath' 2>&1 < /dev/null & " +
        "for i in `$(seq 1 20); do " +
        "[ -s '$PidPath' ] && exit 0; " +
        "sleep 0.1; " +
        "done; " +
        "exit 1"


    [void](
        Invoke-SshCapture `
            $HostName `
            $remote `
            3 `
            2 `
            20
    )
}


function Get-RemoteProcessStatus {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name
    )

    $PidPath =
        "$RunDir/$Name.pid"

    $ExitPath =
        "$RunDir/$Name.exit"


    $remote =
        "if [ -f '$ExitPath' ]; then " +
        "printf 'DONE '; cat '$ExitPath'; " +
        "elif [ -s '$PidPath' ] && " +
        "sudo -n kill -0 -- -`$(cat '$PidPath') 2>/dev/null; then " +
        "echo RUNNING; " +
        "else " +
        "echo LOST; " +
        "fi"


    return (
        Invoke-SshCapture `
            $HostName `
            $remote `
            3 `
            2 `
            20
    ).Trim()
}


function Stop-RemoteProcess {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name,
        [string]$Signal
    )

    $PidPath =
        "$RunDir/$Name.pid"


    $remote =
        "if [ -s '$PidPath' ]; then " +
        "sudo -n kill -$Signal -- -`$(cat '$PidPath') 2>/dev/null || true; " +
        "fi"


    [void](
        Invoke-SshCapture `
            $HostName `
            $remote `
            3 `
            2 `
            20
    )
}


function Wait-RemoteProcessStopped {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name,
        [int]$TimeoutSeconds
    )

    $deadline =
        (Get-Date).AddSeconds($TimeoutSeconds)


    while ((Get-Date) -lt $deadline) {
        $status =
            Get-RemoteProcessStatus `
                $HostName `
                $RunDir `
                $Name


        if ($status -ne "RUNNING") {
            return $true
        }


        Start-Sleep -Milliseconds 500
    }


    return $false
}


# -----------------------------------------------------------------------------
# Clock snapshots.
#
# setup_dpdk_vm.sh owns setup + validation.
# run_pair.ps1 only records clock state before/after the measurement.
# -----------------------------------------------------------------------------

function Get-SenderClockSnapshot {
    return Invoke-SshCapture `
        $SenderSsh `
        (
            "chronyc tracking; " +
            "echo; " +
            "chronyc sources -n -v; " +
            "echo; " +
            "chronyc sourcestats -n -v"
        ) `
        3 `
        2 `
        30
}


function Get-ReceiverClockSnapshot {
    return Invoke-SshCapture `
        $ReceiverSsh `
        (
            "chronyc tracking; " +
            "echo; " +
            "chronyc sources -n -v; " +
            "echo; " +
            "chronyc sourcestats -n -v; " +
            "echo; " +
            "chronyc ntpdata '$SenderManagementIp'"
        ) `
        3 `
        2 `
        30
}


# -----------------------------------------------------------------------------
# Run directory.
# -----------------------------------------------------------------------------

$RunId =
    (Get-Date).ToUniversalTime().ToString(
        "yyyyMMdd-HHmmssfff"
    )

$LocalRunDir =
    Join-Path $OutputRoot $RunId


New-Item `
    -ItemType Directory `
    -Force `
    $LocalRunDir |
    Out-Null


$SenderRunDir =
    "/tmp/lldt-$RunId"

$ReceiverRunDir =
    "/tmp/lldt-$RunId"


Write-Host "Run:          $RunId"
Write-Host "Sender SSH:   $SenderSsh"
Write-Host "Receiver SSH: $ReceiverSsh"
Write-Host "Profile:      $Profile"
Write-Host "Batching:     $([bool]$Batching)"
Write-Host "Rate:         $Rate msg/s"
Write-Host "Samples:      $Samples"
Write-Host


# -----------------------------------------------------------------------------
# SSH / sudo preflight.
# -----------------------------------------------------------------------------

Write-Host "Checking SSH..."


[void](
    Invoke-SshCapture `
        $SenderSsh `
        "echo sender-ssh-ok" `
        3 `
        2 `
        20
)


[void](
    Invoke-SshCapture `
        $ReceiverSsh `
        "echo receiver-ssh-ok" `
        3 `
        2 `
        20
)


Write-Host "Checking passwordless sudo..."


[void](
    Invoke-SshCapture `
        $SenderSsh `
        "sudo -n true" `
        3 `
        2 `
        20
)


[void](
    Invoke-SshCapture `
        $ReceiverSsh `
        "sudo -n true" `
        3 `
        2 `
        20
)


# -----------------------------------------------------------------------------
# Repository consistency.
# -----------------------------------------------------------------------------

Write-Host "Checking commits..."


$SenderCommit =
    Invoke-SshCapture `
        $SenderSsh `
        "cd '$SenderRepo' && git rev-parse HEAD" `
        3 `
        2 `
        20


$ReceiverCommit =
    Invoke-SshCapture `
        $ReceiverSsh `
        "cd '$ReceiverRepo' && git rev-parse HEAD" `
        3 `
        2 `
        20


if ($SenderCommit -ne $ReceiverCommit) {
    throw (
        "Commit mismatch: " +
        "sender=$SenderCommit receiver=$ReceiverCommit"
    )
}


Write-Host "Commit: $SenderCommit"


# -----------------------------------------------------------------------------
# Matched build.
# -----------------------------------------------------------------------------

if (-not $SkipBuild) {
    if ($Profile -eq "compact") {
        $BuildCommand =
            "rm -rf build/lldt_release && " +
            "./scripts/build.sh --compact && " +
            "make -C harness clean && " +
            "make -C harness LLDT_MESSAGE_PROFILE=compact"
    }
    else {
        $BuildCommand =
            "rm -rf build/lldt_release && " +
            "./scripts/build.sh && " +
            "make -C harness clean && " +
            "make -C harness LLDT_MESSAGE_PROFILE=raw"
    }


    Write-Host "Building Sender..."


    [void](
        Invoke-SshCapture `
            $SenderSsh `
            "cd '$SenderRepo' && $BuildCommand" `
            1 `
            0 `
            900
    )


    Write-Host "Building Receiver..."


    [void](
        Invoke-SshCapture `
            $ReceiverSsh `
            "cd '$ReceiverRepo' && $BuildCommand" `
            1 `
            0 `
            900
    )
}


# -----------------------------------------------------------------------------
# Record clock state.
# -----------------------------------------------------------------------------

Write-Host "Recording clock state..."


$SenderClockBefore =
    Get-SenderClockSnapshot


$ReceiverClockBefore =
    Get-ReceiverClockSnapshot


Set-Content `
    (Join-Path $LocalRunDir "sender-clock-before.txt") `
    $SenderClockBefore


Set-Content `
    (Join-Path $LocalRunDir "receiver-clock-before.txt") `
    $ReceiverClockBefore


# -----------------------------------------------------------------------------
# Environment snapshots.
# -----------------------------------------------------------------------------

$EnvironmentCommand = @"
echo '=== git ==='
git rev-parse HEAD
git status --short

echo
echo '=== compiler ==='
g++ --version | head -n 1

echo
echo '=== dpdk ==='
pkg-config --modversion libdpdk || true

echo
echo '=== kernel ==='
uname -a

echo
echo '=== cpu ==='
lscpu -e=CPU,CORE,SOCKET,NODE,ONLINE

echo
echo '=== kernel command line ==='
cat /proc/cmdline

echo
echo '=== hugepages ==='
grep -E 'HugePages_Total|HugePages_Free|Hugepagesize' /proc/meminfo

echo
echo '=== PCI ethernet ==='
lspci -nnk | grep -A3 -i 'Ethernet controller' || true
"@


$SenderEnvironment =
    Invoke-SshCapture `
        $SenderSsh `
        "cd '$SenderRepo' && $EnvironmentCommand" `
        3 `
        2 `
        30


$ReceiverEnvironment =
    Invoke-SshCapture `
        $ReceiverSsh `
        "cd '$ReceiverRepo' && $EnvironmentCommand" `
        3 `
        2 `
        30


Set-Content `
    (Join-Path $LocalRunDir "sender-environment.txt") `
    $SenderEnvironment


Set-Content `
    (Join-Path $LocalRunDir "receiver-environment.txt") `
    $ReceiverEnvironment


# -----------------------------------------------------------------------------
# Manifest.
# -----------------------------------------------------------------------------

$Manifest = [ordered]@{
    run_id                 = $RunId
    commit                 = $SenderCommit

    profile                = $Profile
    batching               = [bool]$Batching

    rate                   = $Rate
    samples                = $Samples
    message_type           = $MessageType
    warmup_seconds         = $WarmupSeconds

    shm                    = $ShmName
    slots                  = $Slots
    data_port              = $DataPort

    sender_public_ip       = $SenderPublicIp
    receiver_public_ip     = $ReceiverPublicIp

    sender_management_ip   = $SenderManagementIp
    receiver_management_ip = $ReceiverManagementIp

    sender_data_ip         = $SenderDataIp
    receiver_data_ip       = $ReceiverDataIp

    next_hop_mac           = $NextHopMac

    setup_precondition     =
        "setup_dpdk_vm.sh completed manually on all VMs"
}


$Manifest |
    ConvertTo-Json -Depth 4 |
    Set-Content `
        (Join-Path $LocalRunDir "manifest.json")


# -----------------------------------------------------------------------------
# Remove stale SHM.
# -----------------------------------------------------------------------------

if (-not $ShmName.StartsWith("/")) {
    throw "SHM name must start with '/': $ShmName"
}


$ShmLeaf =
    $ShmName.TrimStart("/")


if ($ShmLeaf.Contains("/")) {
    throw "Nested POSIX SHM name is not supported: $ShmName"
}


$ShmPath =
    "/dev/shm/$ShmLeaf"


[void](
    Invoke-SshCapture `
        $SenderSsh `
        "sudo -n rm -f '$ShmPath'" `
        3 `
        2 `
        20
)


[void](
    Invoke-SshCapture `
        $ReceiverSsh `
        "sudo -n rm -f '$ShmPath'" `
        3 `
        2 `
        20
)


# -----------------------------------------------------------------------------
# Application commands.
# -----------------------------------------------------------------------------

$BatchArgument = ""

if ($Batching) {
    $BatchArgument = " --batching"
}


$ReceiverCommand =
    "env " +
    "LLDT_SHM=$ShmName " +
    "LLDT_SLOTS=$Slots " +
    "LLDT_DATA_PORT=$DataPort " +
    "./scripts/run_receiver.sh " +
    "$ReceiverDataIp " +
    "$SenderDataIp " +
    "$NextHopMac"


$ProducerCommand =
    "taskset -c 2 ./harness/bin/producer " +
    "--shm $ShmName " +
    "--slots $Slots " +
    "--count 0 " +
    "--rate $Rate " +
    "--type $MessageType"


$SenderCommand =
    "env " +
    "LLDT_SHM=$ShmName " +
    "LLDT_SLOTS=$Slots " +
    "LLDT_DATA_PORT=$DataPort " +
    "./scripts/run_sender.sh " +
    "$SenderDataIp " +
    "$ReceiverDataIp " +
    "$NextHopMac" +
    $BatchArgument


$ConsumerCommand =
    "sudo -n taskset -c 2 ./harness/bin/consumer " +
    "--shm $ShmName " +
    "--slots $Slots " +
    "--from-edge " +
    "--count $Samples " +
    "--idle-ms 10000 " +
    "--csv $ReceiverRunDir/latency.csv"


# -----------------------------------------------------------------------------
# Run state.
# -----------------------------------------------------------------------------

$ReceiverStarted = $false
$ProducerStarted = $false
$SenderStarted = $false
$ConsumerStarted = $false

$Failure = $null


try {
    # -------------------------------------------------------------------------
    # Receiver.
    # -------------------------------------------------------------------------

    Write-Host "Starting Receiver..."


    Start-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRepo `
        $ReceiverRunDir `
        "receiver" `
        $ReceiverCommand


    $ReceiverStarted = $true


    Start-Sleep -Seconds 1


    $status =
        Get-RemoteProcessStatus `
            $ReceiverSsh `
            $ReceiverRunDir `
            "receiver"


    if ($status -ne "RUNNING") {
        throw "Receiver exited during startup: $status"
    }


    # -------------------------------------------------------------------------
    # Producer.
    # -------------------------------------------------------------------------

    Write-Host "Starting Producer..."


    Start-RemoteProcess `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "producer" `
        $ProducerCommand


    $ProducerStarted = $true


    Start-Sleep -Milliseconds 500


    $status =
        Get-RemoteProcessStatus `
            $SenderSsh `
            $SenderRunDir `
            "producer"


    if ($status -ne "RUNNING") {
        throw "Producer exited during startup: $status"
    }


    # -------------------------------------------------------------------------
    # Sender.
    # -------------------------------------------------------------------------

    Write-Host "Starting Sender..."


    Start-RemoteProcess `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "sender" `
        $SenderCommand


    $SenderStarted = $true


    Start-Sleep -Seconds 1


    $status =
        Get-RemoteProcessStatus `
            $SenderSsh `
            $SenderRunDir `
            "sender"


    if ($status -ne "RUNNING") {
        throw "Sender exited during startup: $status"
    }


    # -------------------------------------------------------------------------
    # Warm-up.
    # -------------------------------------------------------------------------

    Write-Host "Warm-up: $WarmupSeconds s"


    Start-Sleep -Seconds $WarmupSeconds


    # -------------------------------------------------------------------------
    # Measured consumer.
    # -------------------------------------------------------------------------

    Write-Host "Starting measured Consumer..."


    Start-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRepo `
        $ReceiverRunDir `
        "consumer" `
        $ConsumerCommand


    $ConsumerStarted = $true


    if ($Rate -gt 0) {
        $ExpectedSeconds =
            [double]$Samples /
            [double]$Rate


        $InitialQuietWaitSeconds =
            [Math]::Max(
                1,
                [int][Math]::Ceiling(
                    $ExpectedSeconds
                ) + 1
            )


        $MeasurementTimeoutSeconds =
            [Math]::Max(
                60,
                [int][Math]::Ceiling(
                    $ExpectedSeconds * 4.0
                ) + 30
            )
    }
    else {
        $InitialQuietWaitSeconds = 2
        $MeasurementTimeoutSeconds = 120
    }


    # -------------------------------------------------------------------------
    # No SSH traffic during expected measured interval.
    # -------------------------------------------------------------------------

    Write-Host (
        "Measured interval: no SSH polling for " +
        "$InitialQuietWaitSeconds s"
    )


    Start-Sleep -Seconds $InitialQuietWaitSeconds


    $MeasurementDeadline =
        (Get-Date).AddSeconds(
            $MeasurementTimeoutSeconds -
            $InitialQuietWaitSeconds
        )


    # -------------------------------------------------------------------------
    # Wait for natural consumer completion.
    # -------------------------------------------------------------------------

    while ($true) {
        $status =
            Get-RemoteProcessStatus `
                $ReceiverSsh `
                $ReceiverRunDir `
                "consumer"


        if ($status.StartsWith("DONE ")) {
            $consumerExitCode =
                [int]$status.Substring(5).Trim()


            if ($consumerExitCode -ne 0) {
                throw (
                    "Consumer failed with exit code " +
                    "$consumerExitCode."
                )
            }


            break
        }


        if ($status -eq "LOST") {
            throw (
                "Consumer disappeared without an exit status."
            )
        }


        if ((Get-Date) -ge $MeasurementDeadline) {
            throw "Consumer timed out."
        }


        Start-Sleep -Seconds 2
    }


    $ConsumerStarted = $false


    # -------------------------------------------------------------------------
    # Validate sample count.
    # -------------------------------------------------------------------------

    $CsvCountOutput =
        Invoke-SshCapture `
            $ReceiverSsh `
            "sudo -n wc -l '$ReceiverRunDir/latency.csv'" `
            3 `
            2 `
            20


    $CsvLineCount =
        [Int64](
            ($CsvCountOutput -split '\s+')[0]
        )


    $ExpectedCsvLines =
        [Int64]$Samples + 1


    if ($CsvLineCount -ne $ExpectedCsvLines) {
        throw (
            "Consumer did not collect the requested " +
            "sample count: CSV lines=$CsvLineCount " +
            "expected=$ExpectedCsvLines"
        )
    }


    Write-Host "Measured phase complete."


    # -------------------------------------------------------------------------
    # Stop Producer.
    # -------------------------------------------------------------------------

    Stop-RemoteProcess `
        $SenderSsh `
        $SenderRunDir `
        "producer" `
        "TERM"


    [void](
        Wait-RemoteProcessStopped `
            $SenderSsh `
            $SenderRunDir `
            "producer" `
            5
    )


    $ProducerStarted = $false


    Start-Sleep -Seconds 1


    # -------------------------------------------------------------------------
    # Stop Sender.
    # -------------------------------------------------------------------------

    Write-Host "Stopping Sender..."


    Stop-RemoteProcess `
        $SenderSsh `
        $SenderRunDir `
        "sender" `
        "INT"


    if (-not (
        Wait-RemoteProcessStopped `
            $SenderSsh `
            $SenderRunDir `
            "sender" `
            10
    )) {
        throw "Sender did not exit after SIGINT."
    }


    $SenderStarted = $false


    # -------------------------------------------------------------------------
    # Stop Receiver.
    # -------------------------------------------------------------------------

    Write-Host "Stopping Receiver..."


    Stop-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRunDir `
        "receiver" `
        "INT"


    if (-not (
        Wait-RemoteProcessStopped `
            $ReceiverSsh `
            $ReceiverRunDir `
            "receiver" `
            10
    )) {
        throw "Receiver did not exit after SIGINT."
    }


    $ReceiverStarted = $false
}
catch {
    $Failure = $_
}
finally {
    # -------------------------------------------------------------------------
    # Best-effort cleanup.
    # -------------------------------------------------------------------------

    if ($ConsumerStarted) {
        try {
            Stop-RemoteProcess `
                $ReceiverSsh `
                $ReceiverRunDir `
                "consumer" `
                "TERM"
        }
        catch {
        }
    }


    if ($ProducerStarted) {
        try {
            Stop-RemoteProcess `
                $SenderSsh `
                $SenderRunDir `
                "producer" `
                "TERM"
        }
        catch {
        }
    }


    if ($SenderStarted) {
        try {
            Stop-RemoteProcess `
                $SenderSsh `
                $SenderRunDir `
                "sender" `
                "INT"
        }
        catch {
        }
    }


    if ($ReceiverStarted) {
        try {
            Stop-RemoteProcess `
                $ReceiverSsh `
                $ReceiverRunDir `
                "receiver" `
                "INT"
        }
        catch {
        }
    }


    Start-Sleep -Seconds 1
}


# -----------------------------------------------------------------------------
# Record final clock state.
# -----------------------------------------------------------------------------

Write-Host "Recording final clock state..."


try {
    $SenderClockAfter =
        Get-SenderClockSnapshot


    Set-Content `
        (Join-Path $LocalRunDir "sender-clock-after.txt") `
        $SenderClockAfter
}
catch {
    Set-Content `
        (Join-Path $LocalRunDir "sender-clock-after-error.txt") `
        $_.Exception.Message
}


try {
    $ReceiverClockAfter =
        Get-ReceiverClockSnapshot


    Set-Content `
        (Join-Path $LocalRunDir "receiver-clock-after.txt") `
        $ReceiverClockAfter
}
catch {
    Set-Content `
        (Join-Path $LocalRunDir "receiver-clock-after-error.txt") `
        $_.Exception.Message
}


# -----------------------------------------------------------------------------
# Make latency CSV readable through SCP.
# -----------------------------------------------------------------------------

try {
    [void](
        Invoke-SshCapture `
            $ReceiverSsh `
            "sudo -n chmod 0644 '$ReceiverRunDir/latency.csv' 2>/dev/null || true" `
            3 `
            2 `
            20
    )
}
catch {
}


# -----------------------------------------------------------------------------
# Collect artifacts.
# -----------------------------------------------------------------------------

Write-Host "Collecting artifacts..."


$Artifacts = @(
    @{
        Host   = $SenderSsh
        Remote = "$SenderRunDir/sender.log"
        Local  = "sender.log"
    },
    @{
        Host   = $SenderSsh
        Remote = "$SenderRunDir/producer.log"
        Local  = "producer.log"
    },
    @{
        Host   = $SenderSsh
        Remote = "$SenderRunDir/sender.exit"
        Local  = "sender.exit"
    },
    @{
        Host   = $SenderSsh
        Remote = "$SenderRunDir/producer.exit"
        Local  = "producer.exit"
    },

    @{
        Host   = $ReceiverSsh
        Remote = "$ReceiverRunDir/receiver.log"
        Local  = "receiver.log"
    },
    @{
        Host   = $ReceiverSsh
        Remote = "$ReceiverRunDir/consumer.log"
        Local  = "consumer.log"
    },
    @{
        Host   = $ReceiverSsh
        Remote = "$ReceiverRunDir/receiver.exit"
        Local  = "receiver.exit"
    },
    @{
        Host   = $ReceiverSsh
        Remote = "$ReceiverRunDir/consumer.exit"
        Local  = "consumer.exit"
    },
    @{
        Host   = $ReceiverSsh
        Remote = "$ReceiverRunDir/latency.csv"
        Local  = "latency.csv"
    }
)


foreach ($Artifact in $Artifacts) {
    try {
        Copy-RemoteFile `
            $Artifact.Host `
            $Artifact.Remote `
            (Join-Path $LocalRunDir $Artifact.Local)
    }
    catch {
        Write-Warning $_
    }
}


if ($null -ne $Failure) {
    throw $Failure
}


Write-Host
Write-Host "Run completed:"
Write-Host "  $LocalRunDir"