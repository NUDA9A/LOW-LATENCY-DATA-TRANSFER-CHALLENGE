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
    (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"), `
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
        "echo '=== chronyc tracking ==='"
        "chronyc tracking"
        "echo"
        "echo '=== chronyc sources ==='"
        "chronyc sources -n -v"
        "echo"
        "} >> '$RunDir/run.log' 2>&1"
    ) -join "; "

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
    # Receiver must be ready before Sender starts transmitting.
    #

    Write-Host "Starting Receiver..."

    $ReceiverCommand = @(
        "set -e"
        "mkdir -p '$ReceiverRunDir'"
        "rm -f /dev/shm/${ShmName#/}"
        "setsid '$ReceiverRepo/scripts/run_receiver.sh' '$ReceiverDataIp' '$SenderDataIp' '$ReceiverNextHopMac' > '$ReceiverRunDir/receiver.log' 2>&1 < /dev/null & echo `$! > '$ReceiverRunDir/receiver.pid'"
    ) -join "; "

    Invoke-Ssh $ReceiverSsh $ReceiverCommand

    Start-Sleep -Seconds 1


    #
    # Producer owns the Sender input SHM, so start it before Sender.
    #

    Write-Host "Starting Producer..."

    $ProducerCommand = @(
        "set -e"
        "mkdir -p '$SenderRunDir'"
        "rm -f /dev/shm/${ShmName#/}"
        "setsid taskset -c 2 '$SenderRepo/harness/bin/producer' --shm '$ShmName' --slots '$Slots' --count 0 --rate '$Rate' --type mixed > '$SenderRunDir/producer.log' 2>&1 < /dev/null & echo `$! > '$SenderRunDir/producer.pid'"
    ) -join "; "

    Invoke-Ssh $SenderSsh $ProducerCommand

    Start-Sleep -Milliseconds 100


    Write-Host "Starting Sender..."

    $SenderCommand = @(
        "set -e"
        "setsid '$SenderRepo/scripts/run_sender.sh' '$SenderDataIp' '$ReceiverDataIp' '$SenderNextHopMac' $BatchingArg > '$SenderRunDir/sender.log' 2>&1 < /dev/null & echo `$! > '$SenderRunDir/sender.pid'"
    ) -join "; "

    Invoke-Ssh $SenderSsh $SenderCommand


    #
    # Let the complete pipeline reach steady state before Consumer begins
    # measuring from the live edge of the output ring.
    #

    Write-Host "Warm-up: $WarmupSeconds s..."
    Start-Sleep -Seconds $WarmupSeconds


    #
    # This SSH command intentionally remains open until Consumer has received
    # exactly Samples messages or exits because of its own idle timeout.
    #

    Write-Host "Starting Consumer..."

    $ConsumerCommand = @(
        "set -e"
        "setsid taskset -c 2 '$ReceiverRepo/harness/bin/consumer' --shm '$ShmName' --slots '$Slots' --from-edge --count '$Samples' --csv '$ReceiverRunDir/latency.csv' > '$ReceiverRunDir/consumer.log' 2>&1 < /dev/null & echo `$! > '$ReceiverRunDir/consumer.pid'"
        "wait `$(cat '$ReceiverRunDir/consumer.pid')"
    ) -join "; "

    Invoke-Ssh $ReceiverSsh $ConsumerCommand

    Write-Host "Consumer finished."
}
finally {
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

    # Give Sender/Receiver enough time to print their final counters.
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
    ) -join "; "

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
    ) -join "; "

    Invoke-SshBestEffort $ReceiverSsh $ReceiverAfter
}


Write-Host
Write-Host "Run completed."
Write-Host "Sender:   $SenderRunDir"
Write-Host "Receiver: $ReceiverRunDir"