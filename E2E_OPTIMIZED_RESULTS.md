## Compact + Batching ON
### (Smoke) Rate 20000, Samples 200000
### Sender
```text
Frames read:    348253
Bytes read:     24145520
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      348253
Data packets built:     348245
Data payload bytes:     24145520
Data sequences consumed:        348245
Tx packets enqueued:    348245
Tx packets unsent:      0
Tx burst calls: 348245
Successfully transmitted packets:       396231
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  348245
tx_q0_bytes:    46433200
tx_drops:       0
tx_q0_bytes:    46433200
tx_q0_missed_tx:        0
Frames per data packet: 1.000023
Data packets per TX burst: 1.000000
```
```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000020 seconds fast of NTP time
Last offset     : +0.000000012 seconds
RMS offset      : 0.000000037 seconds
#* PHC0                          0   0   377     0   +111ns[ +123ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000024 seconds slow of NTP time
Last offset     : -0.000000017 seconds
RMS offset      : 0.000000018 seconds
#* PHC0                          0   0   377     0   -266ns[ -283ns] +/- 5025ns
```

### Receiver
```text
Total received packets: 348246
Total received bytes:   46433242
Total invalid lldt packets:     1
Total stale packets:    214
Total gaps:     0
Total missing packets:  0
Total accepted packets: 348031
Total frames published: 348039
Total bytes published:  24130704
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
latency (ns) : min=12526 mean=14641 max=101482
  p01        : 13111
  p50        : 14435
  p99        : 17897
  p99.9      : 21890
  p99.99     : 47491
```

[Latency distribution](docs/benchmarks/20260826-173644045-r20000-n200000-distribution.png) · [Latency tail](docs/benchmarks/20260826-173644045-r20000-n200000-tail.png)

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000028 seconds slow of NTP time
Last offset     : -0.000000010 seconds
RMS offset      : 0.000000018 seconds
#* PHC0                          0   0   377     0   -147ns[ -157ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000015 seconds fast of NTP time
Last offset     : +0.000000001 seconds
RMS offset      : 0.000000013 seconds
#* PHC0                          0   0   377     0    -43ns[  -42ns] +/- 5025ns
```

### Rate 50'000, Samples 1'000'000
### Sender
```text
Frames read:    1375900
Bytes read:     95395712
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      1375900
Data packets built:     573389
Data payload bytes:     95395712
Data sequences consumed:        573389
Tx packets enqueued:    573389
Tx packets unsent:      0
Tx burst calls: 568965
Successfully transmitted packets:       621375
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  573389
tx_q0_bytes:    132092608
tx_drops:       0
tx_q0_bytes:    132092608
tx_q0_missed_tx:        0
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000002 seconds slow of NTP time
Last offset     : -0.000000000 seconds
RMS offset      : 0.000000011 seconds
#* PHC0                          0   0   367     0    +23ns[  +23ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000019 seconds fast of NTP time
Last offset     : +0.000000020 seconds
RMS offset      : 0.000000043 seconds
#* PHC0                          0   0   377     0   +140ns[ +160ns] +/- 5025ns
```

### Receiver
```text
Total received packets: 573390
Total received bytes:   132092650
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 573389
Total frames published: 1375900
Total bytes published:  95395712
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
received     : 1000000
expected     : 1000000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=12897 mean=23564 max=96936
  p01        : 13849
  p50        : 24679
  p99        : 39061
  p99.9      : 47285
  p99.99     : 83954
```

[Latency distribution](docs/benchmarks/20260826-174448735-r50000-n1000000-distribution.png) · [Latency tail](docs/benchmarks/20260826-174448735-r50000-n1000000-tail.png)

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000028 seconds fast of NTP time
Last offset     : +0.000000058 seconds
RMS offset      : 0.000000106 seconds
#* PHC0                          0   0   377     0   +184ns[ +242ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000000 seconds fast of NTP time
Last offset     : -0.000000023 seconds
RMS offset      : 0.000000098 seconds
#* PHC0                          0   0   377     0    -65ns[  -89ns] +/- 5025ns
```

### Rate 100'000, Samples 2'000'000
### Sender
```text
Frames read:    2782701
Bytes read:     192933936
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      2782701
Data packets built:     949363
Data payload bytes:     192933936
Data sequences consumed:        949363
Tx packets enqueued:    949363
Tx packets unsent:      0
Tx burst calls: 940509
Successfully transmitted packets:       997349
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  949363
tx_q0_bytes:    253693168
tx_drops:       0
tx_q0_bytes:    253693168
tx_q0_missed_tx:        0
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000166 seconds slow of NTP time
Last offset     : -0.000000269 seconds
RMS offset      : 0.000000187 seconds
#* PHC0                          0   0   377     0    -45ns[ -314ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000073 seconds slow of NTP time
Last offset     : -0.000000053 seconds
RMS offset      : 0.000000196 seconds
#* PHC0                          0   0   377     0   +168ns[ +115ns] +/- 5025ns
```

### Receiver
```text
Total received packets: 949364
Total received bytes:   253693210
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 949363
Total frames published: 2782701
Total bytes published:  192933936
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
received     : 2000000
expected     : 2000000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=12268 mean=24946 max=107275
  p01        : 13063
  p50        : 26035
  p99        : 40908
  p99.9      : 48725
  p99.99     : 63267
```

[Latency distribution](docs/benchmarks/20260826-175807166-r100000-n2000000-distribution.png) · [Latency tail](docs/benchmarks/20260826-175807166-r100000-n2000000-tail.png)

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000031 seconds fast of NTP time
Last offset     : +0.000000032 seconds
RMS offset      : 0.000000028 seconds
#* PHC0                          0   0   377     0   +467ns[ +499ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000013 seconds slow of NTP time
Last offset     : -0.000000001 seconds
RMS offset      : 0.000000036 seconds
#* PHC0                          0   0   377     0     -5ns[   -5ns] +/- 5025ns
```

### Rate 200'000, Samples 10'000'000
### Sender
```text
Frames read:    11722420
Bytes read:     812754448
Lapped events:  3
Lapped frames skipped:  380
Invalid frames: 0
Source gap events:      2
Source frames missing:  380
Mbuf alloc failures:    0
Frames packetized:      11722420
Data packets built:     3077087
Data payload bytes:     812754448
Data sequences consumed:        3077087
Tx packets enqueued:    3077087
Tx packets unsent:      0
Tx burst calls: 3039662
Successfully transmitted packets:       3125073
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  3077087
tx_q0_bytes:    1009688016
tx_drops:       0
tx_q0_bytes:    1009688016
tx_q0_missed_tx:        0
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000109 seconds slow of NTP time
Last offset     : -0.000000183 seconds
RMS offset      : 0.000000193 seconds
#* PHC0                          0   0   277     0   -105ns[ -288ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000027 seconds fast of NTP time
Last offset     : +0.000000042 seconds
RMS offset      : 0.000000062 seconds
#* PHC0                          0   0   377     0   +140ns[ +182ns] +/- 5025ns
```

### Receiver
```text
Total received packets: 3077088
Total received bytes:   1009688058
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 3077087
Total frames published: 11722420
Total bytes published:  812754448
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
received     : 10000000
expected     : 10000380
dropped      : 380
drop_rate    : 0.0038%
latency (ns) : min=11676 mean=25813 max=154601
  p01        : 12619
  p50        : 26242
  p99        : 41388
  p99.9      : 60836
  p99.99     : 129870
```

[Latency distribution](docs/benchmarks/20260826-180149443-r200000-n10000000-distribution.png) · [Latency tail](docs/benchmarks/20260826-180149443-r200000-n10000000-tail.png)

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000045 seconds slow of NTP time
Last offset     : -0.000000048 seconds
RMS offset      : 0.000000101 seconds
#* PHC0                          0   0   377     0   -102ns[ -150ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000051 seconds slow of NTP time
Last offset     : -0.000000013 seconds
RMS offset      : 0.000000094 seconds
#* PHC0                          0   0   377     0    +30ns[  +17ns] +/- 5025ns
```

### Rate 400'000, Samples 4'000'000
### Sender
```text
Frames read:    7138800
Bytes read:     494956800
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      7138800
Data packets built:     1437218
Data payload bytes:     494956800
Data sequences consumed:        1437218
Tx packets enqueued:    1437218
Tx packets unsent:      0
Tx burst calls: 1409703
Successfully transmitted packets:       1485204
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  1437218
tx_q0_bytes:    586938752
tx_drops:       0
tx_q0_bytes:    586938752
tx_q0_missed_tx:        0
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000058 seconds slow of NTP time
Last offset     : -0.000000055 seconds
RMS offset      : 0.000000069 seconds
#* PHC0                          0   0   377     0   -185ns[ -240ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000020 seconds fast of NTP time
Last offset     : -0.000000011 seconds
RMS offset      : 0.000000052 seconds
#* PHC0                          0   0   257     0    -49ns[  -59ns] +/- 5025ns
```

### Receiver
```text
Total received packets: 1437218
Total received bytes:   586938752
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 1437218
Total frames published: 7138800
Total bytes published:  494956800
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
received     : 4000000
expected     : 4000000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=11941 mean=26105 max=139147
  p01        : 12835
  p50        : 26023
  p99        : 40680
  p99.9      : 55091
  p99.99     : 65737
```

[Latency distribution](docs/benchmarks/20260826-180454609-r400000-n4000000-distribution.png) · [Latency tail](docs/benchmarks/20260826-180454609-r400000-n4000000-tail.png)

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000034 seconds fast of NTP time
Last offset     : +0.000000025 seconds
RMS offset      : 0.000000056 seconds
#* PHC0                          0   0   377     0    +65ns[  +90ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000012 seconds slow of NTP time
Last offset     : -0.000000028 seconds
RMS offset      : 0.000000028 seconds
#* PHC0                          0   0   377     0   -213ns[ -241ns] +/- 5025ns
```

### Rate 800'000, Samples 8'000'000
### Sender
```text
Frames read:    14712000
Bytes read:     1020032000
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      14712000
Data packets built:     2012652
Data payload bytes:     1020032000
Data sequences consumed:        2012652
Tx packets enqueued:    2012652
Tx packets unsent:      0
Tx burst calls: 1956430
Successfully transmitted packets:       2060638
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  2012652
tx_q0_bytes:    1148841728
tx_drops:       0
tx_q0_bytes:    1148841728
tx_q0_missed_tx:        0
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000006 seconds slow of NTP time
Last offset     : +0.000000010 seconds
RMS offset      : 0.000000018 seconds
#* PHC0                          0   0   377     0   +119ns[ +129ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000005 seconds slow of NTP time
Last offset     : +0.000000006 seconds
RMS offset      : 0.000000053 seconds
#* PHC0                          0   0   377     0    +46ns[  +52ns] +/- 5025ns
```

### Receiver
```text
Total received packets: 2012652
Total received bytes:   1148841728
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 2012652
Total frames published: 14712000
Total bytes published:  1020032000
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
received     : 8000000
expected     : 8000000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=13527 mean=28676 max=27034765
  p01        : 20335
  p50        : 27861
  p99        : 44736
  p99.9      : 64261
  p99.99     : 105599
```

[Latency distribution](docs/benchmarks/20260826-180656990-r800000-n8000000-distribution.png) · [Latency tail](docs/benchmarks/20260826-180656990-r800000-n8000000-tail.png)

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000009 seconds fast of NTP time
Last offset     : +0.000000033 seconds
RMS offset      : 0.000000091 seconds
#* PHC0                          0   0   377     0   +113ns[ +146ns] +/- 5025ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000021 seconds slow of NTP time
Last offset     : -0.000000010 seconds
RMS offset      : 0.000000033 seconds
#* PHC0                          0   0   377     0    -91ns[ -101ns] +/- 5025ns
```

### TX burst experiment — conclusion

The bounded opportunistic TX-burst experiment was not selected for the final implementation.

It improved latency in several runs, including lower p99/p99.9 values, but actual multi-packet TX bursts remained rare: `Data packets per TX burst` stayed close to `1` across the sweep. At the same time, source-frame packing changed substantially compared with the baseline, making the latency improvement difficult to attribute cleanly to TX burst submission alone.

The experiment therefore did not demonstrate a sufficiently clear and isolated benefit to justify the added Sender complexity. The submission baseline remains **Compact + batching ON** with the original single-packet TX submission path.

The measurements above are retained as evidence of the rejected optimization experiment.