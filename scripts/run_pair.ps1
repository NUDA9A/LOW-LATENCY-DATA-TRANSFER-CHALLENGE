param(
    [Parameter(Mandatory = $true)]
    [long]$Rate,

    [Parameter(Mandatory = $true)]
    [long]$Samples,

    [switch]$Batching
)

if ($Rate -le 0) {
    throw "Rate must be > 0."
}

if ($Samples -le 0) {
    throw "Samples must be > 0."
}


$SshKeyPath = "$HOME\.ssh\lldt.pem"

$SenderSsh   = "ubuntu@51.20.212.52"
$ReceiverSsh = "ubuntu@51.21.142.26"

$SenderRepo   = "/home/ubuntu/projects/low-latency-data-transfer-challenge"
$ReceiverRepo = "/home/ubuntu/projects/low-latency-data-transfer-challenge"

$SenderDataIp   = "10.0.1.10"
$ReceiverDataIp = "10.0.1.20"

$SenderNextHopMac   = "06:cd:a3:3f:bc:bb"
$ReceiverNextHopMac = "06:76:72:0f:0d:89"

$ShmName = "/fanout_ring"
$ShmFile = $ShmName.TrimStart("/")

$Slots = 1024
$WarmupSeconds = 5


if (-not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf)) {
    throw "SSH key not found: $SshKeyPath"
}


$SshOptions = @(
    "-T",
    "-i", $SshKeyPath,
    "-o", "IdentitiesOnly=yes",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new"
)


$RunId = "{0}-r{1}-n{2}" -f `
    (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmssfff"), `
    $Rate, `
    $Samples

$SenderRunDir   = "/var/tmp/lldt-benchmark/$RunId"
$ReceiverRunDir = "/var/tmp/lldt-benchmark/$RunId"

$BatchingValue = if ($Batching) { "on" } else { "off" }
$BatchingArg = if ($Batching) { "--batching" } else { "" }


function Invoke-Ssh
{
    param(
        [string]$Target,
        [string]$Command
    )

    & ssh.exe @SshOptions $Target $Command

    if ($LASTEXITCODE -ne 0) {
        throw "SSH command failed on $Target with exit code $LASTEXITCODE."
    }
}


function Invoke-SshBestEffort
{
    param(
        [string]$Target,
        [string]$Command
    )

    & ssh.exe @SshOptions $Target $Command 2>$null | Out-Null
}


function Write-ClockSnapshot
{
    param(
        [string]$Target,
        [string]$Repo,
        [string]$RunDir,
        [string]$Phase
    )

    $Command = @(
        "mkdir -p '$RunDir'"
        "{"
        "echo '=== $Phase ==='"
        "date -u --iso-8601=ns"
        "echo 'rate=$Rate'"
        "echo 'samples=$Samples'"
        "echo 'batching=$BatchingValue'"
        "echo"
        "echo '=== commit ==='"
        "git -C '$Repo' rev-parse HEAD"
        "echo"
        "echo '=== message profile ==='"
        "grep '^LLDT_MESSAGE_PROFILE:' '$Repo/build/lldt_release/CMakeCache.txt' || true"
        "echo"
        "echo '=== chronyc tracking ==='"
        "chronyc tracking"
        "echo"
        "echo '=== chronyc sources ==='"
        "chronyc sources -n -v"
        "echo"
        "} >> '$RunDir/run.log' 2>&1"
    ) -join "`n"

    Invoke-Ssh $Target $Command
}


function Stop-RemoteGroup
{
    param(
        [string]$Target,
        [string]$PidFile,
        [string]$Signal
    )

    $Command =
        "if [ -s '$PidFile' ]; then " +
        "xargs -r -I{} kill -$Signal -- -{} < '$PidFile' 2>/dev/null || true; " +
        "fi"

    Invoke-SshBestEffort $Target $Command
}


Write-Host "Run:      $RunId"
Write-Host "Rate:     $Rate msg/s"
Write-Host "Samples:  $Samples"
Write-Host "Batching: $BatchingValue"
Write-Host


try {
    #
    # Record benchmark clock state before starting datapath processes.
    #

    Write-ClockSnapshot `
        $SenderSsh `
        $SenderRepo `
        $SenderRunDir `
        "before"

    Write-ClockSnapshot `
        $ReceiverSsh `
        $ReceiverRepo `
        $ReceiverRunDir `
        "before"


    #
    # Receiver first.
    #

    Write-Host "Starting Receiver..."

    $ReceiverCommand = @(
        "set -e"
        "mkdir -p '$ReceiverRunDir'"
        "rm -f '/dev/shm/$ShmFile'"
        "setsid '$ReceiverRepo/scripts/run_receiver.sh' '$ReceiverDataIp' '$SenderDataIp' '$ReceiverNextHopMac' > '$ReceiverRunDir/receiver.log' 2>&1 < /dev/null & echo `$! > '$ReceiverRunDir/receiver.pid'"
        "sleep 1"
        "kill -0 `$(cat '$ReceiverRunDir/receiver.pid')"
    ) -join "; "

    Invoke-Ssh $ReceiverSsh $ReceiverCommand


    #
    # Producer creates the input SHM. As soon as the SHM exists, start Sender.
    # SenderShmReader attaches at the live edge, so pre-attach producer frames
    # are intentionally outside the transport stream.
    #

    Write-Host "Starting Producer and Sender..."

    $SenderCommand = @(
        "set -e"
        "mkdir -p '$SenderRunDir'"
        "rm -f '/dev/shm/$ShmFile'"
        "setsid taskset -c 2 '$SenderRepo/harness/bin/producer' --shm '$ShmName' --slots '$Slots' --count 0 --rate '$Rate' --type mixed > '$SenderRunDir/producer.log' 2>&1 < /dev/null & echo `$! > '$SenderRunDir/producer.pid'"
        "for i in `$(seq 1 1000); do grep -q '^producer: shm=' '$SenderRunDir/producer.log' && break; sleep 0.001; done"
        "grep -q '^producer: shm=' '$SenderRunDir/producer.log'"
        "setsid '$SenderRepo/scripts/run_sender.sh' '$SenderDataIp' '$ReceiverDataIp' '$SenderNextHopMac' $BatchingArg > '$SenderRunDir/sender.log' 2>&1 < /dev/null & echo `$! > '$SenderRunDir/sender.pid'"
        "sleep 1"
        "kill -0 `$(cat '$SenderRunDir/sender.pid')"
    ) -join "; "

    Invoke-Ssh $SenderSsh $SenderCommand


    #
    # Warm-up is outside the measured consumer interval.
    #

    Write-Host "Warm-up: $WarmupSeconds s..."
    Start-Sleep -Seconds $WarmupSeconds


    #
    # Consumer attaches at the current output-ring live edge and measures
    # exactly Samples delivered frames.
    #

    Write-Host "Starting Consumer..."

    $ConsumerCommand = @(
        "set -e"
        "setsid sudo -n taskset -c 2 '$ReceiverRepo/harness/bin/consumer' --shm '$ShmName' --slots '$Slots' --from-edge --count '$Samples' --csv '$ReceiverRunDir/latency.csv' > '$ReceiverRunDir/consumer.log' 2>&1 < /dev/null & echo `$! > '$ReceiverRunDir/consumer.pid'"
        "wait `$(cat '$ReceiverRunDir/consumer.pid')"
    ) -join "; "

    Invoke-Ssh $ReceiverSsh $ConsumerCommand

    Write-Host "Consumer finished."
}
finally {
    #
    # Stop source first, then terminate transport cleanly.
    #

    Write-Host "Stopping processes..."

    Stop-RemoteGroup `
        $ReceiverSsh `
        "$ReceiverRunDir/consumer.pid" `
        "INT"

    Stop-RemoteGroup `
        $SenderSsh `
        "$SenderRunDir/producer.pid" `
        "INT"

    Stop-RemoteGroup `
        $SenderSsh `
        "$SenderRunDir/sender.pid" `
        "INT"

    Stop-RemoteGroup `
        $ReceiverSsh `
        "$ReceiverRunDir/receiver.pid" `
        "INT"

    # Sender/Receiver print their counters after leaving their hot loops.
    Start-Sleep -Seconds 2


    $SenderAfter = @(
        "{"
        "echo '=== after ==='"
        "date -u --iso-8601=ns"
        "echo"
        "echo '=== chronyc tracking ==='"
        "chronyc tracking"
        "echo"
        "echo '=== chronyc sources ==='"
        "chronyc sources -n -v"
        "echo"
        "} >> '$SenderRunDir/run.log' 2>&1"
    ) -join "`n"

    Invoke-SshBestEffort $SenderSsh $SenderAfter


    $ReceiverAfter = @(
        "{"
        "echo '=== after ==='"
        "date -u --iso-8601=ns"
        "echo"
        "echo '=== chronyc tracking ==='"
        "chronyc tracking"
        "echo"
        "echo '=== chronyc sources ==='"
        "chronyc sources -n -v"
        "echo"
        "} >> '$ReceiverRunDir/run.log' 2>&1"
    ) -join "`n"

    Invoke-SshBestEffort $ReceiverSsh $ReceiverAfter
}


Write-Host
Write-Host "Run completed."
Write-Host "Sender:   $SenderRunDir"
Write-Host "Receiver: $ReceiverRunDir"