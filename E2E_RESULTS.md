## Raw + Batching OFF
### (Smoke) Rate 20000, Samples 200000
### Sender
```text
Frames read:    407649
Lapped events:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      407649
Data packets built:     407649
Tx packets enqueued:    407649
Tx packets unsent:      0
Successfully transmitted packets:       407680
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  407649
tx_q0_bytes:    156537216
tx_drops:       0
tx_q0_missed_tx:        0
```

=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000032 seconds slow of NTP time
Last offset     : +0.000000020 seconds
RMS offset      : 0.000000168 seconds
#* PHC0                          0   0   377     0   +151ns[ +171ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000248 seconds slow of NTP time
Last offset     : -0.000000302 seconds
RMS offset      : 0.000000177 seconds
#* PHC0                          0   0   377     0   -117ns[ -419ns] +/- 5030ns

### Receiver
```text
Total received packets: 407650
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 407649
Total frames published: 407649
Total packets missed by hardware:       0
Total erroneous received packets:       0
Total Rx mbuf allocation failures:      0
rx_errors:      0
rx_q0_errors:   0
rx_q0_mbuf_alloc_fail:  0
```

### Consumer
```text
consumer: lapped 0 times
---- delivery metrics ----
received     : 200000
expected     : 200000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=11614 mean=72211 max=234817
  p01        : 12833
  p50        : 69986
  p99        : 186804
  p99.9      : 204626
  p99.99     : 217300
```

=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000003 seconds fast of NTP time
Last offset     : +0.000000013 seconds
RMS offset      : 0.000000012 seconds
#* PHC0                          0   0   377     0    +30ns[  +44ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000018 seconds slow of NTP time
Last offset     : -0.000000020 seconds
RMS offset      : 0.000000025 seconds
#* PHC0                          0   0   377     0   -161ns[ -181ns] +/- 5028ns

### Rate 50'000, Samples 1'000'000
### Rate 100'000, Samples 2'000'000
### Rate 200'000, Samples 10'000'000
### Rate 400'000, Samples 4'000'000
### Rate 800'000, Samples 8'000'000
### Rate 1'600'000, Samples 16'000'000

## Raw + Batching ON
### (Smoke) Rate 20000, Samples 200000

### Rate 50'000, Samples 1'000'000
### Rate 100'000, Samples 2'000'000
### Rate 200'000, Samples 10'000'000
### Rate 400'000, Samples 4'000'000
### Rate 800'000, Samples 8'000'000
### Rate 1'600'000, Samples 16'000'000

## Compact + Batching OFF
### (Smoke) Rate 20000, Samples 200000

### Rate 50'000, Samples 1'000'000
### Rate 100'000, Samples 2'000'000
### Rate 200'000, Samples 10'000'000
### Rate 400'000, Samples 4'000'000
### Rate 800'000, Samples 8'000'000
### Rate 1'600'000, Samples 16'000'000

## Compact + Batching ON
### (Smoke) Rate 20000, Samples 200000

### Rate 50'000, Samples 1'000'000
### Rate 100'000, Samples 2'000'000
### Rate 200'000, Samples 10'000'000
### Rate 400'000, Samples 4'000'000
### Rate 800'000, Samples 8'000'000
### Rate 1'600'000, Samples 16'000'000