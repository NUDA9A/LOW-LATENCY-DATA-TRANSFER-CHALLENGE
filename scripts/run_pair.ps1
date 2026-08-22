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


# ----------------------------------------------------------------------
# SSH configuration.
# ----------------------------------------------------------------------

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
    "-o", "ConnectTimeout=10",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=4"
)

$ScpOptions = @(
    "-i", $SshKeyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=10",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=4"
)


# ----------------------------------------------------------------------
# Helpers.
# ----------------------------------------------------------------------

function Invoke-SshCapture {
    param(
        [string]$HostName,
        [string]$Command
    )

    $output =
        & ssh.exe @SshOptions $HostName $Command 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw (
            "SSH command failed on ${HostName}:`n" +
            ($output -join "`n")
        )
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

    # setsid gives every remotely launched application its own process group.
    # This lets us later signal the whole group, including sudo/child processes.
    $remote =
        "cd '$Repo' || exit 1; " +
        "mkdir -p '$RunDir' || exit 1; " +
        "nohup setsid $Command " +
        "> '$RunDir/$Name.log' 2>&1 < /dev/null & " +
        "echo `$! > '$RunDir/$Name.pid'"

    [void](Invoke-SshCapture $HostName $remote)
}


function Test-RemoteProcess {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name
    )

    $command =
        "pid=`$(cat '$RunDir/$Name.pid' 2>/dev/null) || exit 1; " +
        "sudo -n kill -0 -- -`$pid 2>/dev/null"

    & ssh.exe @SshOptions $HostName $command *> $null

    return ($LASTEXITCODE -eq 0)
}


function Stop-RemoteProcess {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name,
        [string]$Signal
    )

    $command =
        "pid=`$(cat '$RunDir/$Name.pid' 2>/dev/null) || exit 0; " +
        "sudo -n kill -$Signal -- -`$pid 2>/dev/null || true"

    & ssh.exe @SshOptions $HostName $command *> $null
}


function Wait-RemoteProcessExit {
    param(
        [string]$HostName,
        [string]$RunDir,
        [string]$Name,
        [int]$TimeoutSeconds
    )

    $deadline =
        (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        if (-not (
            Test-RemoteProcess `
                $HostName `
                $RunDir `
                $Name
        )) {
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

    & scp.exe @ScpOptions `
        "${HostName}:$RemotePath" `
        $LocalPath

    if ($LASTEXITCODE -ne 0) {
        throw "SCP failed: ${HostName}:$RemotePath"
    }
}


# ----------------------------------------------------------------------
# Run directories.
# ----------------------------------------------------------------------

$RunId =
    (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssfff")

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


# ----------------------------------------------------------------------
# SSH / sudo preflight.
# ----------------------------------------------------------------------

Write-Host "Checking SSH..."

[void](Invoke-SshCapture `
    $SenderSsh `
    "echo sender-ssh-ok")

[void](Invoke-SshCapture `
    $ReceiverSsh `
    "echo receiver-ssh-ok")


Write-Host "Checking passwordless sudo..."

[void](Invoke-SshCapture `
    $SenderSsh `
    "sudo -n true")

[void](Invoke-SshCapture `
    $ReceiverSsh `
    "sudo -n true")


# ----------------------------------------------------------------------
# Repository consistency.
# ----------------------------------------------------------------------

Write-Host "Checking commits..."

$SenderCommit =
    Invoke-SshCapture `
        $SenderSsh `
        "cd '$SenderRepo' && git rev-parse HEAD"

$ReceiverCommit =
    Invoke-SshCapture `
        $ReceiverSsh `
        "cd '$ReceiverRepo' && git rev-parse HEAD"

if ($SenderCommit -ne $ReceiverCommit) {
    throw (
        "Commit mismatch: " +
        "sender=$SenderCommit receiver=$ReceiverCommit"
    )
}

Write-Host "Commit: $SenderCommit"


# ----------------------------------------------------------------------
# Matched build.
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

    [void](Invoke-SshCapture `
        $SenderSsh `
        "cd '$SenderRepo' && $BuildCommand")

    Write-Host "Building Receiver..."

    [void](Invoke-SshCapture `
        $ReceiverSsh `
        "cd '$ReceiverRepo' && $BuildCommand")
}


# ----------------------------------------------------------------------
# Clock preflight.
# ----------------------------------------------------------------------

Write-Host "Checking clock synchronization..."

$SenderClockBefore =
    Invoke-SshCapture `
        $SenderSsh `
        "cd '$SenderRepo' && ./scripts/check_clock_sync.sh"

$ReceiverClockBefore =
    Invoke-SshCapture `
        $ReceiverSsh `
        "cd '$ReceiverRepo' && ./scripts/check_clock_sync.sh '$SenderManagementIp'"

Set-Content `
    (Join-Path $LocalRunDir "sender-clock-before.txt") `
    $SenderClockBefore

Set-Content `
    (Join-Path $LocalRunDir "receiver-clock-before.txt") `
    $ReceiverClockBefore


# ----------------------------------------------------------------------
# Environment snapshots.
# ----------------------------------------------------------------------

$EnvironmentCommand = @"
echo '=== git ==='
git rev-parse HEAD
git status --short

echo
echo '=== compiler ==='
g++ --version | head -n 1

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

echo
echo '=== chrony ==='
chronyc tracking
"@

$SenderEnvironment =
    Invoke-SshCapture `
        $SenderSsh `
        "cd '$SenderRepo' && $EnvironmentCommand"

$ReceiverEnvironment =
    Invoke-SshCapture `
        $ReceiverSsh `
        "cd '$ReceiverRepo' && $EnvironmentCommand"

Set-Content `
    (Join-Path $LocalRunDir "sender-environment.txt") `
    $SenderEnvironment

Set-Content `
    (Join-Path $LocalRunDir "receiver-environment.txt") `
    $ReceiverEnvironment


# ----------------------------------------------------------------------
# Manifest.
# ----------------------------------------------------------------------

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
}

$Manifest |
    ConvertTo-Json -Depth 4 |
    Set-Content `
        (Join-Path $LocalRunDir "manifest.json")


# ----------------------------------------------------------------------
# Remove stale SHM from previous interrupted runs.
# ----------------------------------------------------------------------

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

[void](Invoke-SshCapture `
    $SenderSsh `
    "sudo -n rm -f '$ShmPath'")

[void](Invoke-SshCapture `
    $ReceiverSsh `
    "sudo -n rm -f '$ShmPath'")


# ----------------------------------------------------------------------
# Commands.
# ----------------------------------------------------------------------

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


# ----------------------------------------------------------------------
# Run.
# ----------------------------------------------------------------------

$ReceiverStarted = $false
$ProducerStarted = $false
$SenderStarted = $false
$ConsumerStarted = $false

$Failure = $null


try {
    # Receiver ---------------------------------------------------------

    Write-Host "Starting Receiver..."

    Start-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRepo `
        $ReceiverRunDir `
        "receiver" `
        $ReceiverCommand

    $ReceiverStarted = $true

    Start-Sleep -Seconds 1

    if (-not (
        Test-RemoteProcess `
            $ReceiverSsh `
            $ReceiverRunDir `
            "receiver"
    )) {
        throw "Receiver exited during startup."
    }


    # Producer ---------------------------------------------------------

    Write-Host "Starting Producer..."

    Start-RemoteProcess `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "producer" `
        $ProducerCommand

    $ProducerStarted = $true

    Start-Sleep -Milliseconds 500

    if (-not (
        Test-RemoteProcess `
            $SenderSsh `
            $SenderRunDir `
            "producer"
    )) {
        throw "Producer exited during startup."
    }


    # Sender -----------------------------------------------------------

    Write-Host "Starting Sender..."

    Start-RemoteProcess `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "sender" `
        $SenderCommand

    $SenderStarted = $true

    Start-Sleep -Seconds 1

    if (-not (
        Test-RemoteProcess `
            $SenderSsh `
            $SenderRunDir `
            "sender"
    )) {
        throw "Sender exited during startup."
    }

    if (-not (
        Test-RemoteProcess `
            $ReceiverSsh `
            $ReceiverRunDir `
            "receiver"
    )) {
        throw "Receiver exited during Sender startup."
    }


    # Warm-up ----------------------------------------------------------

    Write-Host "Warm-up: $WarmupSeconds s"

    Start-Sleep -Seconds $WarmupSeconds


    # Measured consumer ------------------------------------------------

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
            [Math]::Max(
                [double]$Rate,
                1.0
            )
        )

    $TimeoutSeconds =
        [Math]::Max(
            60,
            [int]($ExpectedSeconds * 4 + 30)
        )

    $MeasuredDeadline =
        (Get-Date).AddSeconds($TimeoutSeconds)


    while (
        Test-RemoteProcess `
            $ReceiverSsh `
            $ReceiverRunDir `
            "consumer"
    ) {
        if (-not (
            Test-RemoteProcess `
                $ReceiverSsh `
                $ReceiverRunDir `
                "receiver"
        )) {
            throw "Receiver exited during measured phase."
        }

        if (-not (
            Test-RemoteProcess `
                $SenderSsh `
                $SenderRunDir `
                "sender"
        )) {
            throw "Sender exited during measured phase."
        }

        if (-not (
            Test-RemoteProcess `
                $SenderSsh `
                $SenderRunDir `
                "producer"
        )) {
            throw "Producer exited during measured phase."
        }

        if ((Get-Date) -ge $MeasuredDeadline) {
            throw "Consumer timed out."
        }

        Start-Sleep -Milliseconds 500
    }


    $ConsumerStarted = $false


    # Consumer can also terminate due to its idle timeout. Require exactly
    # the requested number of stored samples before accepting the run.

    $CsvLineCountText =
        Invoke-SshCapture `
            $ReceiverSsh `
            "sudo -n sh -c `"wc -l < '$ReceiverRunDir/latency.csv'`""

    $CsvLineCount =
        [Int64]$CsvLineCountText

    $ExpectedCsvLines =
        [Int64]$Samples + 1

    if ($CsvLineCount -ne $ExpectedCsvLines) {
        throw (
            "Consumer did not collect the requested sample count: " +
            "CSV lines=$CsvLineCount expected=$ExpectedCsvLines"
        )
    }

    Write-Host "Measured phase complete."


    # Stop source traffic ----------------------------------------------

    Stop-RemoteProcess `
        $SenderSsh `
        $SenderRunDir `
        "producer" `
        "TERM"

    [void](
        Wait-RemoteProcessExit `
            $SenderSsh `
            $SenderRunDir `
            "producer" `
            5
    )

    $ProducerStarted = $false

    Start-Sleep -Seconds 1


    # Clock snapshots after measurement -------------------------------

    $SenderClockAfter =
        Invoke-SshCapture `
            $SenderSsh `
            "chronyc tracking; echo; chronyc sources -v"

    $ReceiverClockAfter =
        Invoke-SshCapture `
            $ReceiverSsh `
            (
                "chronyc tracking; " +
                "echo; " +
                "chronyc sources -v; " +
                "echo; " +
                "chronyc ntpdata '$SenderManagementIp'"
            )

    Set-Content `
        (Join-Path $LocalRunDir "sender-clock-after.txt") `
        $SenderClockAfter

    Set-Content `
        (Join-Path $LocalRunDir "receiver-clock-after.txt") `
        $ReceiverClockAfter


    # Sender shutdown --------------------------------------------------

    Write-Host "Stopping Sender..."

    Stop-RemoteProcess `
        $SenderSsh `
        $SenderRunDir `
        "sender" `
        "INT"

    if (-not (
        Wait-RemoteProcessExit `
            $SenderSsh `
            $SenderRunDir `
            "sender" `
            10
    )) {
        throw "Sender did not exit after SIGINT."
    }

    $SenderStarted = $false


    # Receiver shutdown ------------------------------------------------

    Write-Host "Stopping Receiver..."

    Stop-RemoteProcess `
        $ReceiverSsh `
        $ReceiverRunDir `
        "receiver" `
        "INT"

    if (-not (
        Wait-RemoteProcessExit `
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
# Make root-owned latency CSV readable through SCP.
# ----------------------------------------------------------------------

& ssh.exe @SshOptions `
    $ReceiverSsh `
    "sudo -n chmod 0644 '$ReceiverRunDir/latency.csv' 2>/dev/null || true" `
    *> $null


# ----------------------------------------------------------------------
# Collect artifacts.
# ----------------------------------------------------------------------

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