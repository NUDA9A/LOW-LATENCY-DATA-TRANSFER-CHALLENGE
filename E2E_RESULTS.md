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

```text
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
```

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

```text
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
```

### Rate 50'000, Samples 1'000'000
### Sender
```text
Frames read:    1530304
Bytes read:     489684864
Lapped events:  907
Lapped frames skipped:  1159
Invalid frames: 9
Source gap events:      2239
Source frames missing:  3377
Mbuf alloc failures:    0
Frames packetized:      1530295
Data packets built:     1530295
Data payload bytes:     489681600
Tx packets enqueued:    1471294
Tx packets unsent:      59001
Successfully transmitted packets:       1471325
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  1471294
tx_q0_bytes:    564992128
tx_drops:       0
tx_q0_bytes:    564992128
tx_q0_missed_tx:        0
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000009 seconds slow of NTP time
Last offset     : +0.000000003 seconds
RMS offset      : 0.000000016 seconds
#* PHC0                          0   0   377     0    +38ns[  +40ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000035 seconds slow of NTP time
Last offset     : -0.000000029 seconds
RMS offset      : 0.000000124 seconds
#* PHC0                          0   0   377     0   -112ns[ -141ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 1471173
Total received bytes:   564945194
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     1599
Total missing packets:  59123
Total accepted packets: 1471172
Total frames published: 1471172
Total bytes published:  470790144
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
expected     : 1039197
dropped      : 39197
drop_rate    : 3.7719%
latency (ns) : min=11370 mean=292767 max=962830
  p01        : 12849
  p50        : 289905
  p99        : 642755
  p99.9      : 747844
  p99.99     : 918536
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000144 seconds fast of NTP time
Last offset     : +0.000000245 seconds
RMS offset      : 0.000000228 seconds
#* PHC0                          0   0   377     0   +483ns[ +729ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000020 seconds slow of NTP time
Last offset     : -0.000000022 seconds
RMS offset      : 0.000000261 seconds
#* PHC0                          0   0   377     0     -4ns[  -25ns] +/- 5028ns
```


### Raw + Batching OFF — conclusion

At `20k msg/s` the path is clean: no source lapping, no TX loss, no receiver gaps.

At `50k msg/s` saturation is reproducible:
- Sender `rte_eth_tx_burst(..., 1)` starts returning `0`;
- every unsent packet corresponds to a Receiver missing data sequence;
- ENA/AWS allowance counters, RX errors and hardware misses stay at zero;
- Sender also begins falling behind Producer SHM, causing lapping/source gaps;
- latency increases sharply into hundreds of microseconds.

Likely bottleneck: per-packet TX path with `tx_burst(..., 1)` and no retry/bursting, causing descriptor pressure and backpressure into the input SHM.

Main directions to investigate later:
- batching multiple source frames into fewer UDP packets;
- TX burst batching instead of one packet per `rte_eth_tx_burst`;
- TX descriptor/reclaim behavior and queue sizing;
- only after that, consider bounded retry/pending-send handling.

## Raw + Batching ON
### (Smoke) Rate 20000, Samples 200000
### Sender
```text
Frames read:    348374
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      348374
Data packets built:     348374
Data payload bytes:     111479808
Tx packets enqueued:    348374
Tx packets unsent:      0
Successfully transmitted packets:       348405
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  348374
tx_q0_bytes:    133775744
tx_drops:       0
tx_q0_bytes:    133775744
tx_q0_missed_tx:        0
Frames per data packet: 1.000000
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000132 seconds fast of NTP time
Last offset     : +0.000000138 seconds
RMS offset      : 0.000000093 seconds
#* PHC0                          0   0   377     0   +133ns[ +271ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000028 seconds slow of NTP time
Last offset     : -0.000000014 seconds
RMS offset      : 0.000000061 seconds
#* PHC0                          0   0   377     0    -58ns[  -72ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 348374
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 348374
Total frames published: 348374
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
latency (ns) : min=12726 mean=15552 max=50331
  p01        : 13635
  p50        : 15312
  p99        : 19655
  p99.9      : 28397
  p99.99     : 39479
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000001 seconds fast of NTP time
Last offset     : +0.000000010 seconds
RMS offset      : 0.000000012 seconds
#* PHC0                          0   0   377     0   +143ns[ +153ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000001 seconds fast of NTP time
Last offset     : -0.000000009 seconds
RMS offset      : 0.000000036 seconds
#* PHC0                          0   0   377     0    -63ns[  -72ns] +/- 5028ns
```

### Rate 50'000, Samples 1'000'000
### Sender
```text
Frames read:    1377678
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      1377678
Data packets built:     765702
Data payload bytes:     440856960
Tx packets enqueued:    765702
Tx packets unsent:      0
Successfully transmitted packets:       765733
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  765702
tx_q0_bytes:    489861888
tx_drops:       0
tx_q0_bytes:    489861888
tx_q0_missed_tx:        0

Frames per data packet: 1.799235
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000015 seconds fast of NTP time
Last offset     : +0.000000021 seconds
RMS offset      : 0.000000028 seconds
#* PHC0                          0   0   377     0   +188ns[ +209ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000003 seconds slow of NTP time
Last offset     : +0.000000004 seconds
RMS offset      : 0.000000013 seconds
#* PHC0                          0   0   377     0    -69ns[  -65ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 765702
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 765702
Total frames published: 1377678
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
latency (ns) : min=11690 mean=35230 max=97588
  p01        : 12566
  p50        : 40111
  p99        : 63871
  p99.9      : 73081
  p99.99     : 82671
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000006 seconds slow of NTP time
Last offset     : -0.000000006 seconds
RMS offset      : 0.000000016 seconds
#* PHC0                          0   0   377     0   -175ns[ -181ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000043 seconds fast of NTP time
Last offset     : +0.000000028 seconds
RMS offset      : 0.000000015 seconds
#* PHC0                          0   0   377     0   +362ns[ +390ns] +/- 5028ns
```

### Rate 100'000, Samples 2'000'000
### Sender
```text
Frames read:    2763900
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      2763900
Data packets built:     1266362
Data payload bytes:     884448000
Tx packets enqueued:    1266362
Tx packets unsent:      0
Successfully transmitted packets:       1266393
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  1266362
tx_q0_bytes:    965495168
tx_drops:       0
tx_q0_bytes:    965495168
tx_q0_missed_tx:        0

Frames per data packet: 2.182551
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000014 seconds fast of NTP time
Last offset     : -0.000000001 seconds
RMS offset      : 0.000000027 seconds
#* PHC0                          0   0   377     0     -8ns[   -9ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000020 seconds fast of NTP time
Last offset     : +0.000000008 seconds
RMS offset      : 0.000000054 seconds
#* PHC0                          0   0   377     0    +42ns[  +50ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 1266363
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 1266362
Total frames published: 2763900
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
latency (ns) : min=11650 mean=74455 max=223376
  p01        : 12563
  p50        : 74924
  p99        : 155366
  p99.9      : 178632
  p99.99     : 202417
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000015 seconds slow of NTP time
Last offset     : -0.000000012 seconds
RMS offset      : 0.000000032 seconds
#* PHC0                          0   0   377     0   -136ns[ -148ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000022 seconds slow of NTP time
Last offset     : -0.000000021 seconds
RMS offset      : 0.000000015 seconds
#* PHC0                          0   0   377     0   -183ns[ -204ns] +/- 5028ns
```

### Rate 200'000, Samples 10'000'000
### Sender
```text
Frames read:    11770800
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      11770800
Data packets built:     4816495
Data payload bytes:     3766656000
Tx packets enqueued:    4809946
Tx packets unsent:      6549
Successfully transmitted packets:       4809977
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  4809946
tx_q0_bytes:    4068337024
tx_drops:       0
tx_q0_bytes:    4068337024
tx_q0_missed_tx:        0

Frames per data packet: 2.443852
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000027 seconds slow of NTP time
Last offset     : -0.000000024 seconds
RMS offset      : 0.000000019 seconds
#* PHC0                          0   0   377     0   -204ns[ -228ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000027 seconds fast of NTP time
Last offset     : +0.000000017 seconds
RMS offset      : 0.000000033 seconds
#* PHC0                          0   0   377     0   +150ns[ +167ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 4809947
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     485
Total missing packets:  6549
Total accepted packets: 4809946
Total frames published: 11751618
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
expected     : 10010934
dropped      : 10934
drop_rate    : 0.1092%
latency (ns) : min=11115 mean=193352 max=619078
  p01        : 12266
  p50        : 187551
  p99        : 418983
  p99.9      : 456521
  p99.99     : 494352
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000008 seconds fast of NTP time
Last offset     : -0.000000012 seconds
RMS offset      : 0.000000038 seconds
#* PHC0                          0   0   377     0    -58ns[  -69ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000013 seconds slow of NTP time
Last offset     : +0.000000005 seconds
RMS offset      : 0.000000051 seconds
#* PHC0                          0   0   377     0    +27ns[  +32ns] +/- 5028ns
```

### Rate 400'000, Samples 4'000'000
### Sender
```text
Frames read:    8404206
Lapped events:  5916
Lapped frames skipped:  5394
Invalid frames: 25
Source gap events:      2052
Source frames missing:  7399
Mbuf alloc failures:    0
Frames packetized:      8404181
Data packets built:     3125147
Data payload bytes:     2689314624
Tx packets enqueued:    2444650
Tx packets unsent:      680497
Successfully transmitted packets:       2444681
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  2444650
tx_q0_bytes:    2217469312
tx_drops:       0
tx_q0_bytes:    2217469312
tx_q0_missed_tx:        0

Frames per data packet: 2.689211
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000015 seconds slow of NTP time
Last offset     : -0.000000007 seconds
RMS offset      : 0.000000020 seconds
#* PHC0                          0   0   377     0    -90ns[  -96ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000020 seconds fast of NTP time
Last offset     : +0.000000023 seconds
RMS offset      : 0.000000048 seconds
#* PHC0                          0   0   377     0   +173ns[ +196ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 2444650
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     50833
Total missing packets:  680497
Total accepted packets: 2444650
Total frames published: 6444998
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
expected     : 5213132
dropped      : 1213132
drop_rate    : 23.2707%
latency (ns) : min=10748 mean=291873 max=637455
  p01        : 12431
  p50        : 370785
  p99        : 449109
  p99.9      : 532675
  p99.99     : 620321
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000002 seconds fast of NTP time
Last offset     : +0.000000012 seconds
RMS offset      : 0.000000041 seconds
#* PHC0                          0   0   377     0    +81ns[  +93ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000004 seconds fast of NTP time
Last offset     : +0.000000012 seconds
RMS offset      : 0.000000031 seconds
#* PHC0                          0   0   377     0    +79ns[  +90ns] +/- 5028ns
```

### Raw + Batching ON — conclusion

Batching substantially improves throughput compared with Raw + Batching OFF:

- clean at `50k` and `100k msg/s`;
- at `200k msg/s` loss is small (`0.1092%`);
- at `400k msg/s` the sender is clearly saturated (`23.27%` consumer drop rate).

At `400k`:

- `3,125,147` packets built;
- `680,497` packets were rejected locally by `rte_eth_tx_burst`;
- Receiver reports exactly `680,497` missing packets;
- every successfully enqueued packet reaches Receiver;
- no ENA/AWS allowance, RX, or hardware errors are observed;
- Sender also starts falling behind the producer SHM.

Average batching reaches `2.69 frames/packet`, but Raw messages are large enough that packet-count reduction is limited.

Likely bottleneck remains the Sender TX path rather than the network.

Potential improvements:
- submit arrays of mbufs through `rte_eth_tx_burst` instead of one packet per call;
- investigate TX descriptor reclaim/queue behavior;
- add bounded pending/retry handling for temporary `tx_burst == 0`;
- reduce packet rate further — Compact profile should directly help here by fitting considerably more frames per packet.

## Compact + Batching OFF
### (Smoke) Rate 20000, Samples 200000
### Sender
```text
Frames read:    349392
Lapped events:  191
Lapped frames skipped:  288
Invalid frames: 3
Source gap events:      991
Source frames missing:  1275
Mbuf alloc failures:    0
Frames packetized:      349389
Data packets built:     349389
Data payload bytes:     24224144
Tx packets enqueued:    348892
Tx packets unsent:      497
Successfully transmitted packets:       348923
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  348892
tx_q0_bytes:    46518720
tx_drops:       0
tx_q0_bytes:    46518720
tx_q0_missed_tx:        0

Frames per data packet: 1.000000
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000029 seconds fast of NTP time
Last offset     : +0.000000039 seconds
RMS offset      : 0.000000055 seconds
#* PHC0                          0   0   377     0   +284ns[ +323ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000007 seconds fast of NTP time
Last offset     : -0.000000000 seconds
RMS offset      : 0.000000023 seconds
#* PHC0                          0   0   377     0     -1ns[   -1ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 348893
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     10
Total missing packets:  497
Total accepted packets: 348892
Total frames published: 348892
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
latency (ns) : min=11767 mean=209542 max=464711
  p01        : 13099
  p50        : 209664
  p99        : 417338
  p99.9      : 450604
  p99.99     : 461882
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000002 seconds fast of NTP time
Last offset     : +0.000000011 seconds
RMS offset      : 0.000000013 seconds
#* PHC0                          0   0   377     0   +149ns[ +160ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000038 seconds fast of NTP time
Last offset     : +0.000000029 seconds
RMS offset      : 0.000000015 seconds
#* PHC0                          0   0   377     0   +391ns[ +420ns] +/- 5028ns
```

### Rate 50'000, Samples 1'000'000
### Sender
```text
Frames read:    1531934
Lapped events:  339576
Lapped frames skipped:  381239
Invalid frames: 5816
Source gap events:      775968
Source frames missing:  1140564
Mbuf alloc failures:    0
Frames packetized:      1526118
Data packets built:     1526118
Data payload bytes:     105543920
Tx packets enqueued:    1246700
Tx packets unsent:      279418
Successfully transmitted packets:       1246731
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  1246700
tx_q0_bytes:    165965696
tx_drops:       0
tx_q0_bytes:    165965696
tx_q0_missed_tx:        0

Frames per data packet: 1.000000
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000031 seconds slow of NTP time
Last offset     : -0.000000022 seconds
RMS offset      : 0.000000016 seconds
#* PHC0                          0   0   377     0   -204ns[ -225ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000016 seconds slow of NTP time
Last offset     : +0.000000007 seconds
RMS offset      : 0.000000051 seconds
#* PHC0                          0   0   377     0    +64ns[  +71ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 1246700
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     5436
Total missing packets:  279418
Total accepted packets: 1246700
Total frames published: 1246700
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
expected     : 1534303
dropped      : 534303
drop_rate    : 34.8238%
latency (ns) : min=11166 mean=326438 max=813020
  p01        : 12368
  p50        : 320390
  p99        : 641198
  p99.9      : 708040
  p99.99     : 793407
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000010 seconds fast of NTP time
Last offset     : +0.000000008 seconds
RMS offset      : 0.000000012 seconds
#* PHC0                          0   0   377     0   +208ns[ +216ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000041 seconds fast of NTP time
Last offset     : +0.000000043 seconds
RMS offset      : 0.000000020 seconds
#* PHC0                          0   0   377     0   +231ns[ +273ns] +/- 5028ns
```

### Compact + Batching OFF — conclusion

Compact without batching does not materially improve the packet-rate ceiling.

At `50k msg/s` the path is clearly saturated:
- `279,418` packets are rejected locally by Sender TX;
- Receiver reports exactly `279,418` missing packets;
- ENA/AWS allowance and RX error counters remain clean;
- severe input-SHM lapping appears as Sender falls behind Producer.

The Compact representation greatly reduces bytes per frame, but with batching disabled the transport still performs:

`1 source frame -> 1 UDP packet -> 1 rte_eth_tx_burst(..., 1)`

Therefore packet rate, TX descriptor/reclaim pressure and per-packet Sender work remain essentially unchanged. This further points to the Sender TX path, rather than network bandwidth, as the bottleneck.

## Compact + Batching ON
### (Smoke) Rate 20000, Samples 200000
### Sender
```text
Frames read:    349380
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      349380
Data packets built:     73380
Data payload bytes:     24223680
Tx packets enqueued:    73380
Tx packets unsent:      0
Successfully transmitted packets:       73411
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  73380
tx_q0_bytes:    28920000
tx_drops:       0
tx_q0_bytes:    28920000
tx_q0_missed_tx:        0

Frames per data packet: 4.761243
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000002 seconds slow of NTP time
Last offset     : -0.000000012 seconds
RMS offset      : 0.000000017 seconds
#* PHC0                          0   0   377     0   -141ns[ -152ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000006 seconds slow of NTP time
Last offset     : +0.000000005 seconds
RMS offset      : 0.000000010 seconds
#* PHC0                          0   0   377     0   +155ns[ +160ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 73380
Total invalid lldt packets:     0
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 73380
Total frames published: 349380
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
latency (ns) : min=11816 mean=28525 max=68556
  p01        : 13238
  p50        : 28046
  p99        : 49372
  p99.9      : 59588
  p99.99     : 65919
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000012 seconds fast of NTP time
Last offset     : +0.000000005 seconds
RMS offset      : 0.000000016 seconds
#* PHC0                          0   0   377     0   +178ns[ +183ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000019 seconds fast of NTP time
Last offset     : -0.000000000 seconds
RMS offset      : 0.000000042 seconds
#* PHC0                          0   0   377     0     -3ns[   -3ns] +/- 5028ns
```

### Rate 50'000, Samples 1'000'000
### Sender
```text
Frames read:    1375500
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      1375500
Data packets built:     271812
Data payload bytes:     95368000
Tx packets enqueued:    271812
Tx packets unsent:      0
Successfully transmitted packets:       271843
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  271812
tx_q0_bytes:    112763968
tx_drops:       0
tx_q0_bytes:    112763968
tx_q0_missed_tx:        0

Frames per data packet: 5.060483
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000026 seconds slow of NTP time
Last offset     : -0.000000026 seconds
RMS offset      : 0.000000024 seconds
#* PHC0                          0   0   377     0   -331ns[ -357ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000035 seconds fast of NTP time
Last offset     : +0.000000026 seconds
RMS offset      : 0.000000030 seconds
#* PHC0                          0   0   377     0   +258ns[ +284ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 271813
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 271812
Total frames published: 1375500
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
latency (ns) : min=11066 mean=27754 max=96408
  p01        : 12529
  p50        : 27124
  p99        : 47980
  p99.9      : 81038
  p99.99     : 90419
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000116 seconds fast of NTP time
Last offset     : +0.000000230 seconds
RMS offset      : 0.000000186 seconds
#* PHC0                          0   0   377     0   +269ns[ +498ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000039 seconds fast of NTP time
Last offset     : +0.000000279 seconds
RMS offset      : 0.000000187 seconds
#* PHC0                          0   0   377     0    -25ns[ +254ns] +/- 5028ns
```

### Rate 100'000, Samples 2'000'000
### Sender
```text
Frames read:    2767500
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      2767500
Data packets built:     530123
Data payload bytes:     191880000
Tx packets enqueued:    530123
Tx packets unsent:      0
Successfully transmitted packets:       530154
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  530123
tx_q0_bytes:    225807872
tx_drops:       0
tx_q0_bytes:    225807872
tx_q0_missed_tx:        0

Frames per data packet: 5.220487
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000015 seconds fast of NTP time
Last offset     : +0.000000021 seconds
RMS offset      : 0.000000016 seconds
#* PHC0                          0   0   377     0   +106ns[ +127ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000011 seconds slow of NTP time
Last offset     : +0.000000006 seconds
RMS offset      : 0.000000016 seconds
#* PHC0                          0   0   377     0   +378ns[ +405ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 530124
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 530123
Total frames published: 2767500
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
latency (ns) : min=11198 mean=28400 max=115119
  p01        : 12499
  p50        : 27674
  p99        : 47111
  p99.9      : 95633
  p99.99     : 111400
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000102 seconds fast of NTP time
Last offset     : +0.000000108 seconds
RMS offset      : 0.000000199 seconds
#* PHC0                          0   0   377     0   -157ns[  -49ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000066 seconds slow of NTP time
Last offset     : -0.000000115 seconds
RMS offset      : 0.000000161 seconds
#* PHC0                          0   0   377     0   -212ns[ -326ns] +/- 5028ns
```

### Rate 200'000, Samples 10'000'000
### Sender
```text
Frames read:    11793000
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      11793000
Data packets built:     2052463
Data payload bytes:     817648000
Tx packets enqueued:    2052463
Tx packets unsent:      0
Successfully transmitted packets:       2052494
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  2052463
tx_q0_bytes:    949005632
tx_drops:       0
tx_q0_bytes:    949005632
tx_q0_missed_tx:        0

Frames per data packet: 5.745780
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000012 seconds fast of NTP time
Last offset     : +0.000000023 seconds
RMS offset      : 0.000000033 seconds
#* PHC0                          0   0   377     0   +303ns[ +325ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000023 seconds slow of NTP time
Last offset     : -0.000000008 seconds
RMS offset      : 0.000000099 seconds
#* PHC0                          0   0   377     0    -56ns[  -63ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 2052464
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 2052463
Total frames published: 11793000
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
expected     : 10000000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=10126 mean=28204 max=105988
  p01        : 12181
  p50        : 27183
  p99        : 50623
  p99.9      : 67527
  p99.99     : 81929
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000051 seconds fast of NTP time
Last offset     : +0.000000107 seconds
RMS offset      : 0.000000161 seconds
#* PHC0                          0   0   377     0   +186ns[ +294ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000133 seconds slow of NTP time
Last offset     : -0.000000213 seconds
RMS offset      : 0.000000192 seconds
#* PHC0                          0   0   377     0    -22ns[ -235ns] +/- 5028ns
```

### Rate 400'000, Samples 4'000'000
### Sender
```text
Frames read:    6555906
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      6555906
Data packets built:     986144
Data payload bytes:     454542816
Tx packets enqueued:    986144
Tx packets unsent:      0
Successfully transmitted packets:       986175
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  986144
tx_q0_bytes:    517656032
tx_drops:       0
tx_q0_bytes:    517656032
tx_q0_missed_tx:        0

Frames per data packet: 6.648021
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000016 seconds slow of NTP time
Last offset     : -0.000000007 seconds
RMS offset      : 0.000000011 seconds
#* PHC0                          0   0   377     0     -5ns[  -12ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000030 seconds fast of NTP time
Last offset     : +0.000000030 seconds
RMS offset      : 0.000000015 seconds
#* PHC0                          0   0   377     0   +362ns[ +392ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 986145
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 986144
Total frames published: 6555906
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
latency (ns) : min=13294 mean=28901 max=69033771
  p01        : 19040
  p50        : 27082
  p99        : 47554
  p99.9      : 59248
  p99.99     : 70817
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000036 seconds slow of NTP time
Last offset     : -0.000000154 seconds
RMS offset      : 0.000000158 seconds
#* PHC0                          0   0   377     0   -202ns[ -356ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000001 seconds slow of NTP time
Last offset     : -0.000000003 seconds
RMS offset      : 0.000000187 seconds
#* PHC0                          0   0   377     0     +5ns[   +3ns] +/- 5028ns
```

### Rate 800'000, Samples 8'000'000
### Sender
```text
Frames read:    10511506
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      10511506
Data packets built:     1643380
Data payload bytes:     728797728
Tx packets enqueued:    1643380
Tx packets unsent:      0
Successfully transmitted packets:       1643411
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  1643380
tx_q0_bytes:    833974048
tx_drops:       0
tx_q0_bytes:    833974048
tx_q0_missed_tx:        0

Frames per data packet: 6.396272
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000005 seconds fast of NTP time
Last offset     : -0.000000014 seconds
RMS offset      : 0.000000066 seconds
#* PHC0                          0   0   377     0    -36ns[  -51ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000019 seconds slow of NTP time
Last offset     : -0.000000008 seconds
RMS offset      : 0.000000023 seconds
#* PHC0                          0   0   377     0    -88ns[  -96ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 1643381
Total invalid lldt packets:     1
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 1643380
Total frames published: 10511506
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
latency (ns) : min=13512 mean=31761 max=75032131
  p01        : 20667
  p50        : 29333
  p99        : 53583
  p99.9      : 74743
  p99.99     : 101949
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000218 seconds slow of NTP time
Last offset     : -0.000000254 seconds
RMS offset      : 0.000000189 seconds
#* PHC0                          0   0   377     0     -4ns[ -258ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000028 seconds fast of NTP time
Last offset     : -0.000000014 seconds
RMS offset      : 0.000000119 seconds
#* PHC0                          0   0   377     0    -38ns[  -53ns] +/- 5028ns
```

### Rate 1'600'000, Samples 16'000'000
### Sender
```text
Frames read:    18686293
Lapped events:  0
Lapped frames skipped:  0
Invalid frames: 0
Source gap events:      0
Source frames missing:  0
Mbuf alloc failures:    0
Frames packetized:      18686293
Data packets built:     3015616
Data payload bytes:     1295582960
Tx packets enqueued:    3015616
Tx packets unsent:      0
Successfully transmitted packets:       3015647
Failed transmitted packets:     0
tx_errors:      0
tx_q0_packets:  3015616
tx_q0_bytes:    1488582384
tx_drops:       0
tx_q0_bytes:    1488582384
tx_q0_missed_tx:        0

Frames per data packet: 6.196509
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000012 seconds fast of NTP time
Last offset     : -0.000000004 seconds
RMS offset      : 0.000000030 seconds
#* PHC0                          0   0   377     0    -33ns[  -37ns] +/- 5030ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000033 seconds fast of NTP time
Last offset     : +0.000000041 seconds
RMS offset      : 0.000000036 seconds
#* PHC0                          0   0   377     0   +126ns[ +167ns] +/- 5030ns
```

### Receiver
```text
Total received packets: 3015618
Total invalid lldt packets:     2
Total stale packets:    0
Total gaps:     0
Total missing packets:  0
Total accepted packets: 3015616
Total frames published: 18686293
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
received     : 16000000
expected     : 16000000
dropped      : 0
drop_rate    : 0.0000%
latency (ns) : min=13546 mean=32107 max=81039369
  p01        : 20677
  p50        : 29607
  p99        : 56276
  p99.9      : 78343
  p99.99     : 148284
```

```text
=== before ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000018 seconds fast of NTP time
Last offset     : +0.000000010 seconds
RMS offset      : 0.000000041 seconds
#* PHC0                          0   0   377     0    +62ns[  +72ns] +/- 5028ns
=== after ===
Reference ID    : 50484330 (PHC0)
System time     : 0.000000008 seconds slow of NTP time
Last offset     : -0.000000005 seconds
RMS offset      : 0.000000028 seconds
#* PHC0                          0   0   377     0    -43ns[  -48ns] +/- 5028ns
```

### Compact + Batching ON — conclusion

Compact + batching is the strongest configuration tested.

Across all meaningful measured loads there were:

- `0` Sender source gaps / lapping;
- `0` TX unsent packets;
- `0` Receiver missing packets;
- `0` Consumer drops.

Batching reduced packet rate substantially, reaching approximately `5.75 frames/packet` at `200k msg/s` and `6.65 frames/packet` at `400k msg/s`.

At `200k msg/s` E2E latency was:

- p50: `27.2 us`
- p99: `50.6 us`
- p99.9: `67.5 us`
- p99.99: `81.9 us`

No transport saturation was observed before the benchmark producer itself became the limiting factor.

The producer ceiling was measured separately on the Sender machine using the Compact mixed workload with pacing disabled (`--rate 0`):

`16,000,000 messages / 23.10 s ≈ 693,000 msg/s`

```text
/usr/bin/time -f 'elapsed: %e s' \
taskset -c 2 \
./harness/bin/producer \
    --shm /producer_rate_probe \
    --slots 1024 \
    --count 16000000 \
    --rate 0 \
    --type mixed
producer: shm=/producer_rate_probe slots=1024 count=16000000 rate=0 type=mixed
producer: sent 16000000 messages
elapsed: 23.10 s
```

Therefore the practical producer ceiling on this machine is approximately **700k msg/s**. Requested `800k` and `1.6M msg/s` runs should not be interpreted as actually reaching those offered rates.

Compared with the agent baseline at `200k msg/s`, this implementation has a better median (`27.2 us` vs approximately `35 us`) but somewhat worse tail latency (`81.9 us` vs approximately `68 us` at p99.99). The comparison is indicative rather than strictly apples-to-apples because the runs were not executed in an identical benchmark environment.

Overall, Compact + batching sustains the maximum load the current producer can generate with no observable transport loss.

## E2E benchmark conclusion

The four-way Raw/Compact × batching ablation shows that packet rate, rather than network bandwidth, is the primary limitation of the current transport path.

Without batching, both Raw and Compact saturate around `50k msg/s`. Compact alone does not solve the problem because the path still performs one UDP packet and one `rte_eth_tx_burst(..., 1)` call per source message.

Raw + batching substantially improves throughput:
- clean through `100k msg/s`;
- only `0.1092%` consumer loss at `200k msg/s`;
- clear saturation at `400k msg/s` with `23.27%` consumer loss.

Compact + batching changes the result materially:
- approximately `5–6.6` source frames are carried per Data packet;
- no Sender SHM loss;
- no TX enqueue loss;
- no Receiver packet loss;
- no Consumer drops were observed up to the maximum load generated by the producer.

Observed losses in the weaker configurations were localized to the Sender TX path: successfully enqueued packets consistently reached the Receiver, while Receiver missing sequences matched Sender unsent packets. ENA/RX/hardware error counters did not indicate an independent network-loss problem.

The maximum producer rate was measured separately with Compact mixed messages and pacing disabled:
`16,000,000 / 23.10 s ≈ 693k msg/s`.
Thus approximately **700k msg/s** is the current harness-generation ceiling, and transport saturation for Compact + batching was not reached.

At the representative `200k msg/s` point, Compact + batching achieved:

- p50: `27.2 us`
- p99: `50.6 us`
- p99.9: `67.5 us`
- p99.99: `81.9 us`
- drop rate: `0%`

For reference, the agent baseline reports approximately `35 / 39 / 50 / 68 us` for p50/p99/p99.9/p99.99 at `200k msg/s`. Our result therefore improves median latency while trailing the agent baseline in the tail. This comparison should be treated as indicative because the benchmark environments are not strictly identical.

The E2E evidence therefore selects **Compact + batching ON** as the clear default configuration for further development.