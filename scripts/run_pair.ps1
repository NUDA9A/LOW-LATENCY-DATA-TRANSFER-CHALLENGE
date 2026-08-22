param(
    [string]$SenderSsh = "sender@10.129.0.17",
    [string]$ReceiverSsh = "receiver@10.129.0.18",

    [string]$SenderRepo =
        "/home/sender/projects/low-latency-data-transfer-challenge",
    [string]$ReceiverRepo =
        "/home/receiver/projects/low-latency-data-transfer-challenge",

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

    [string]$OutputRoot = ".\results"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SshOptions = @(
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=10"
)

$ScpOptions = @(
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=10"
)


function Invoke-SshCapture {
    param(
        [string]$HostName,
        [string]$Command
    )

    $output = & ssh.exe @SshOptions $HostName $Command 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "SSH command failed on ${HostName}:`n$($output -join "`n")"
    }

    return ($output -join "`n").Trim()
}


function Start-RemoteProcess {
    param(
        [string]$HostName,
        [string]$Repo,
        [string]$RunDir,
        [string]$Name,
        [string]$Command
    )

    $remote =
        "cd '$Repo' && " +
        "mkdir -p '$RunDir' && " +
        "nohup $Command > '$RunDir/$Name.log' 2>&1 < /dev/null & " +
        "echo `$! > '$RunDir/$Name.pid'"

    [void](Invoke-SshCapture $HostName $remote)
}


function Test-RemoteProcess {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name
    )

    & ssh.exe @SshOptions $HostName `
        "sudo -n kill -0 `$(cat '$RunDir/$Name.pid') 2>/dev/null" `
        *> $null

    return ($LASTEXITCODE -eq 0)
}


function Stop-RemoteProcess {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name,
        [string]$Signal
    )

    & ssh.exe @SshOptions $HostName `
        "sudo -n kill -$Signal `$(cat '$RunDir/$Name.pid') 2>/dev/null || true" `
        *> $null
}


function Wait-RemoteProcessExit {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if (-not (Test-RemoteProcess $HostName $RunDir $Name)) {
            return $true
        }

        Start-Sleep -Milliseconds 250
    }

    return $false
}


function Copy-RemoteFile {
    param(
        [string]$HostName,
        [string]$RemotePath,
        [string]$LocalPath
    )

    & scp.exe @ScpOptions "${HostName}:$RemotePath" $LocalPath

    if ($LASTEXITCODE -ne 0) {
        throw "SCP failed: ${HostName}:$RemotePath"
    }
}


$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")

$LocalRunDir = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force $LocalRunDir | Out-Null

$SenderRunDir = "/tmp/lldt-$RunId"
$ReceiverRunDir = "/tmp/lldt-$RunId"


Write-Host "Run: $RunId"


# ----------------------------------------------------------------------
# SSH / sudo preflight
# ----------------------------------------------------------------------

[void](Invoke-SshCapture $SenderSsh "sudo -n true")
[void](Invoke-SshCapture $ReceiverSsh "sudo -n true")


# ----------------------------------------------------------------------
# Repository consistency
# ----------------------------------------------------------------------

$SenderCommit =
    Invoke-SshCapture $SenderSsh `
        "cd '$SenderRepo' && git rev-parse HEAD"

$ReceiverCommit =
    Invoke-SshCapture $ReceiverSsh `
        "cd '$ReceiverRepo' && git rev-parse HEAD"

if ($SenderCommit -ne $ReceiverCommit) {
    throw "Commit mismatch: sender=$SenderCommit receiver=$ReceiverCommit"
}


# ----------------------------------------------------------------------
# Matched build
# ----------------------------------------------------------------------

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
    [void](Invoke-SshCapture $SenderSsh `
        "cd '$SenderRepo' && $BuildCommand")

    Write-Host "Building Receiver..."
    [void](Invoke-SshCapture $ReceiverSsh `
        "cd '$ReceiverRepo' && $BuildCommand")
}


# ----------------------------------------------------------------------
# Clock preflight
# ----------------------------------------------------------------------

Write-Host "Checking clock synchronization..."

$SenderClockBefore =
    Invoke-SshCapture $SenderSsh `
        "chronyc tracking; echo; chronyc sources -v"

$ReceiverClockBefore =
    Invoke-SshCapture $ReceiverSsh `
        "cd '$ReceiverRepo' && ./scripts/check_clock_sync.sh '$SenderManagementIp'"

Set-Content `
    (Join-Path $LocalRunDir "sender-clock-before.txt") `
    $SenderClockBefore

Set-Content `
    (Join-Path $LocalRunDir "receiver-clock-before.txt") `
    $ReceiverClockBefore


# ----------------------------------------------------------------------
# Environment snapshots
# ----------------------------------------------------------------------

$EnvironmentCommand = @"
echo '=== git ==='
git rev-parse HEAD
git status --short

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
    Invoke-SshCapture $SenderSsh `
        "cd '$SenderRepo' && $EnvironmentCommand"

$ReceiverEnvironment =
    Invoke-SshCapture $ReceiverSsh `
        "cd '$ReceiverRepo' && $EnvironmentCommand"

Set-Content `
    (Join-Path $LocalRunDir "sender-environment.txt") `
    $SenderEnvironment

Set-Content `
    (Join-Path $LocalRunDir "receiver-environment.txt") `
    $ReceiverEnvironment


# ----------------------------------------------------------------------
# Manifest
# ----------------------------------------------------------------------

$Manifest = [ordered]@{
    run_id               = $RunId
    commit               = $SenderCommit

    profile              = $Profile
    batching             = [bool]$Batching
    rate                 = $Rate
    samples              = $Samples
    message_type         = $MessageType
    warmup_seconds       = $WarmupSeconds

    slots                = $Slots
    data_port            = $DataPort

    sender_ssh           = $SenderSsh
    receiver_ssh         = $ReceiverSsh

    sender_management_ip = $SenderManagementIp
    sender_data_ip       = $SenderDataIp
    receiver_data_ip     = $ReceiverDataIp
    next_hop_mac         = $NextHopMac
}

$Manifest |
    ConvertTo-Json -Depth 4 |
    Set-Content (Join-Path $LocalRunDir "manifest.json")


$BatchArgument = ""
if ($Batching) {
    $BatchArgument = " --batching"
}


$ReceiverCommand =
    "env " +
    "LLDT_SHM=/fanout_ring " +
    "LLDT_SLOTS=$Slots " +
    "LLDT_DATA_PORT=$DataPort " +
    "./scripts/run_receiver.sh " +
    "$ReceiverDataIp $SenderDataIp $NextHopMac"


$ProducerCommand =
    "taskset -c 2 ./harness/bin/producer " +
    "--shm /fanout_ring " +
    "--slots $Slots " +
    "--count 0 " +
    "--rate $Rate " +
    "--type $MessageType"


$SenderCommand =
    "env " +
    "LLDT_SHM=/fanout_ring " +
    "LLDT_SLOTS=$Slots " +
    "LLDT_DATA_PORT=$DataPort " +
    "./scripts/run_sender.sh " +
    "$SenderDataIp $ReceiverDataIp $NextHopMac" +
    $BatchArgument


$ConsumerCommand =
    "sudo -n taskset -c 2 ./harness/bin/consumer " +
    "--shm /fanout_ring " +
    "--slots $Slots " +
    "--from-edge " +
    "--count $Samples " +
    "--idle-ms 10000 " +
    "--csv $ReceiverRunDir/latency.csv"


$ReceiverStarted = $false
$ProducerStarted = $false
$SenderStarted = $false
$ConsumerStarted = $false
$Failure = $null


try {
    # --------------------------------------------------------------
    # Receiver first
    # --------------------------------------------------------------

    Write-Host "Starting Receiver..."

    Start-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRepo `
        $ReceiverRunDir `
        "receiver" `
        $ReceiverCommand

    $ReceiverStarted = $true

    Start-Sleep -Seconds 1


    # --------------------------------------------------------------
    # Producer creates input SHM and runs continuously.
    # Startup frames are deliberately outside the measured window.
    # --------------------------------------------------------------

    Write-Host "Starting Producer..."

    Start-RemoteProcess `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "producer" `
        $ProducerCommand

    $ProducerStarted = $true

    Start-Sleep -Milliseconds 500


    # --------------------------------------------------------------
    # Sender
    # --------------------------------------------------------------

    Write-Host "Starting Sender..."

    Start-RemoteProcess `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "sender" `
        $SenderCommand

    $SenderStarted = $true


    if (-not (Test-RemoteProcess $ReceiverSsh $ReceiverRunDir "receiver")) {
        throw "Receiver exited during startup."
    }

    if (-not (Test-RemoteProcess $SenderSsh $SenderRunDir "sender")) {
        throw "Sender exited during startup."
    }


    # --------------------------------------------------------------
    # Warm-up
    # --------------------------------------------------------------

    Write-Host "Warm-up: $WarmupSeconds s"
    Start-Sleep -Seconds $WarmupSeconds


    # --------------------------------------------------------------
    # Consumer establishes live edge here: measured phase starts.
    # --------------------------------------------------------------

    Write-Host "Starting measured Consumer..."

    Start-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRepo `
        $ReceiverRunDir `
        "consumer" `
        $ConsumerCommand

    $ConsumerStarted = $true


    $ExpectedSeconds =
        [Math]::Ceiling(
            [double]$Samples /
            [Math]::Max([double]$Rate, 1.0)
        )

    $TimeoutSeconds =
        [Math]::Max(
            60,
            [int]($ExpectedSeconds * 4 + 30)
        )


    while (Test-RemoteProcess $ReceiverSsh $ReceiverRunDir "consumer") {
        if (-not (Test-RemoteProcess $ReceiverSsh $ReceiverRunDir "receiver")) {
            throw "Receiver exited during measured phase."
        }

        if (-not (Test-RemoteProcess $SenderSsh $SenderRunDir "sender")) {
            throw "Sender exited during measured phase."
        }

        Start-Sleep -Milliseconds 500

        $TimeoutSeconds--

        if ($TimeoutSeconds -le 0) {
            throw "Consumer timed out."
        }
    }

    $ConsumerStarted = $false

    Write-Host "Measured phase complete."


    # Stop producer first so no new frames enter Sender.
    Stop-RemoteProcess `
        $SenderSsh `
        $SenderRunDir `
        "producer" `
        "TERM"

    $ProducerStarted = $false

    Start-Sleep -Seconds 1


    # --------------------------------------------------------------
    # Clock snapshot immediately after measured phase
    # --------------------------------------------------------------

    $SenderClockAfter =
        Invoke-SshCapture $SenderSsh `
            "chronyc tracking; echo; chronyc sources -v"

    $ReceiverClockAfter =
        Invoke-SshCapture $ReceiverSsh `
            "chronyc tracking; echo; chronyc sources -v; echo; chronyc ntpdata '$SenderManagementIp'"

    Set-Content `
        (Join-Path $LocalRunDir "sender-clock-after.txt") `
        $SenderClockAfter

    Set-Content `
        (Join-Path $LocalRunDir "receiver-clock-after.txt") `
        $ReceiverClockAfter


    # --------------------------------------------------------------
    # Graceful transport shutdown
    # --------------------------------------------------------------

    Stop-RemoteProcess `
        $SenderSsh `
        $SenderRunDir `
        "sender" `
        "INT"

    [void](Wait-RemoteProcessExit `
        $SenderSsh `
        $SenderRunDir `
        "sender" `
        10)

    $SenderStarted = $false


    Stop-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRunDir `
        "receiver" `
        "INT"

    [void](Wait-RemoteProcessExit `
        $ReceiverSsh `
        $ReceiverRunDir `
        "receiver" `
        10)

    $ReceiverStarted = $false
}
catch {
    $Failure = $_
}
finally {
    if ($ConsumerStarted) {
        Stop-RemoteProcess `
            $ReceiverSsh `
            $ReceiverRunDir `
            "consumer" `
            "TERM"
    }

    if ($ProducerStarted) {
        Stop-RemoteProcess `
            $SenderSsh `
            $SenderRunDir `
            "producer" `
            "TERM"
    }

    if ($SenderStarted) {
        Stop-RemoteProcess `
            $SenderSsh `
            $SenderRunDir `
            "sender" `
            "INT"
    }

    if ($ReceiverStarted) {
        Stop-RemoteProcess `
            $ReceiverSsh `
            $ReceiverRunDir `
            "receiver" `
            "INT"
    }

    Start-Sleep -Seconds 1
}


# ----------------------------------------------------------------------
# Make measurement file readable over SCP.
# ----------------------------------------------------------------------

& ssh.exe @SshOptions $ReceiverSsh `
    "sudo -n chmod 0644 '$ReceiverRunDir/latency.csv' 2>/dev/null || true" `
    *> $null


# ----------------------------------------------------------------------
# Collect run artifacts
# ----------------------------------------------------------------------

Write-Host "Collecting artifacts..."

$Artifacts = @(
    @{
        Host = $SenderSsh
        Remote = "$SenderRunDir/sender.log"
        Local = "sender.log"
    },
    @{
        Host = $SenderSsh
        Remote = "$SenderRunDir/producer.log"
        Local = "producer.log"
    },
    @{
        Host = $ReceiverSsh
        Remote = "$ReceiverRunDir/receiver.log"
        Local = "receiver.log"
    },
    @{
        Host = $ReceiverSsh
        Remote = "$ReceiverRunDir/consumer.log"
        Local = "consumer.log"
    },
    @{
        Host = $ReceiverSsh
        Remote = "$ReceiverRunDir/latency.csv"
        Local = "latency.csv"
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