[Resume — Ivan Akimenko](Akimenko_Ivan_resume.pdf)

## Development process and AI assistance

I used **ChatGPT 5.6 Sol** throughout the project as an architecture, planning, and review assistant.

ChatGPT helped me:

- reason about the transport architecture and performance trade-offs;
- decompose the implementation into small sequential tasks;
- formulate implementation specifications and acceptance criteria;
- review completed changes and benchmark results;
- discuss rejected alternatives and further optimization directions.

The C++ implementation was written and integrated by me. ChatGPT was used primarily for architecture, task specification, technical discussion, and review rather than as an autonomous coding agent.

# Low-Latency Data Transfer Challenge — Solution

## Overview

The solution implements a low-latency unicast market-data transport between two machines using DPDK and UDP.

The end-to-end pipeline is:

```text
Producer
  -> shared-memory ring
  -> SenderShmReader
  -> LLDT packet construction / source-frame batching
  -> DPDK TX
  -> Ethernet / IPv4 / UDP
  -> DPDK RX
  -> LLDT packet parsing
  -> ReceiverShmWriter
  -> shared-memory ring
  -> Consumer
```

The final selected configuration is:

- **Compact message profile**
- **source-frame batching enabled**
- **DPDK userspace networking**
- **one TX queue / one RX queue**
- **1500-byte Ethernet MTU**
- **single-packet `rte_eth_tx_burst(..., 1)` submission in the final Sender**

The wire protocol is documented separately in [WIRE_PROTOCOL.md](WIRE_PROTOCOL.md).

---

## Architecture

### Sender

The Sender busy-polls the Producer shared-memory ring through `SenderShmReader`.

`SenderShmReader` owns validation of the source SHM boundary and source-sequence continuity. Successfully validated frames are passed further through a lightweight trusted view rather than being revalidated by downstream components.

For every Data packet the Sender:

1. reads the first available source frame;
2. reserves a DPDK mbuf;
3. writes an LLDT Data packet directly into the mbuf payload;
4. when batching is enabled, opportunistically appends additional complete source frames while:
    - frames are already available;
    - they fit into the current packet;
    - no source gap boundary is crossed;
5. materializes the Ethernet/IPv4/UDP headers;
6. submits the packet to the DPDK TX queue.

Batching is intentionally **opportunistic**: the Sender never waits for future frames just to fill a packet. This avoids introducing artificial batching latency.

The LLDT Data header contains an independent monotonically increasing `data_seq` and the number of source records in the packet. Source sequence numbers remain part of the source messages and are independent from transport packet numbering.

The maximum canonical UDP payload is 1472 bytes for an Ethernet MTU of 1500 bytes.

The L2/L3/L4 destination template is prepared once. Per packet, only the fields that depend on packet length are updated. IPv4 checksum construction is done in software; the UDP checksum is left zero for IPv4.

### Receiver

The Receiver busy-polls the DPDK RX queue using bursts of up to 32 mbufs.

For each received packet it:

1. validates/parses the Ethernet + IPv4 + UDP + LLDT envelope;
2. checks the LLDT `data_seq`;
3. classifies stale packets and packet gaps;
4. publishes all contained source frames to the output shared-memory ring;
5. frees received mbufs in bulk after processing the RX burst.

The Consumer then attaches to the output SHM ring and uses the original source `seq_id` and `send_ts_ns` to calculate drop rate and end-to-end latency.

### Message profiles

Two compile-time message profiles are retained:

- **Raw** — the original large source representation;
- **Compact** — an optimized representation constructed directly by the Producer.

The Compact profile does not add a Raw-to-Compact encode/decode stage to the transport. Producer, Sender, Receiver and Consumer use the selected source ABI directly.

Compact frame sizes are:

| Message | Raw | Compact |
|---|---:|---:|
| Trade | 192 B | 64 B |
| BBO | 192 B | 48 B |
| OrderBook | 576 B | 96 B |

The Compact representation replaces repeated strings with an instrument identifier and uses fixed-point integer fields and bounded intra-message deltas where the supplied workload permits it. Frames remain independently decodable; no frame depends on a previously received frame.

Reducing source-frame size is particularly important because it allows substantially more source messages to be carried by a single UDP packet.

### Shutdown and diagnostics

Sender and Receiver handle `SIGINT` / `SIGTERM`, leave their hot loops cleanly and print transport, DPDK and driver counters on shutdown.

These counters were used extensively during benchmarking to distinguish:

- source-SHM lapping;
- local TX rejection;
- receiver packet gaps;
- hardware/RX errors;
- end-consumer source-message loss.

---

## Build

The implementation uses C++17 and DPDK 25.11.2.

The supplied scripts build DPDK locally with a minimal configuration and then build the Sender and Receiver in Release mode with `-march=native` and interprocedural optimization.

### Compact profile

Run on both benchmark machines:

```bash
make -C harness clean
make -C harness LLDT_MESSAGE_PROFILE=compact

./scripts/build.sh --compact
```

### Raw profile

```bash
make -C harness clean
make -C harness LLDT_MESSAGE_PROFILE=raw

./scripts/build.sh
```

The Producer/Consumer and Sender/Receiver must always be built with the same message profile.

`scripts/build.sh` invokes the dependency/bootstrap path automatically. DPDK is built statically with the required networking drivers.

---

## Benchmark environment

The end-to-end measurements were performed on two AWS EC2 instances:

- **2 × `m7i.2xlarge`**
- **Ubuntu 24.04**
- one machine used as Sender/Producer;
- one machine used as Receiver/Consumer.

The instances were placed in the same AWS cluster/placement environment with Precision Time support.

System time was synchronized through the Amazon Precision Time/PTP hardware clock. During the benchmark runs `chrony` selected `PHC0` as its active clock source.

Clock state was captured on both machines before and after every benchmark run. The recorded offsets were normally in the sub-microsecond range and are included together with the benchmark results.

### CPU isolation

`scripts/setup_dpdk_vm.sh` configures the benchmark VM for the datapath:

- SMT disabled;
- cores `2,3` isolated;
- `nohz_full=2,3`;
- `rcu_nocbs=2,3`;
- housekeeping/IRQ affinity moved to cores `0,1`;
- `irqbalance` disabled;
- 2 MiB hugepages configured;
- datapath NIC bound to `igb_uio`.

`setup_dpdk_vm.sh` uses the `dpdk-devbind.py` installed by the local DPDK build, so DPDK must be built before the VM setup script is run for the first time.

Assuming the build steps above have been completed, first-time VM setup is:

```bash
sudo ./scripts/setup_dpdk_vm.sh
sudo reboot
```

After reconnecting:

```bash
sudo ./scripts/setup_dpdk_vm.sh
```

The first setup invocation installs the persistent GRUB isolation/hugepage configuration and requests a reboot. The second invocation performs the remaining runtime setup, including binding the datapath NIC to `igb_uio`.

The script expects one management Ethernet device and one separate datapath Ethernet device.

During benchmarking:

- Producer runs on isolated core `2` of the Sender VM;
- Sender DPDK loop runs on isolated core `3`;
- Consumer runs on isolated core `2` of the Receiver VM;
- Receiver DPDK loop runs on isolated core `3`.

---

## Running an E2E benchmark

The main benchmark orchestrator is:

```text
scripts/run_pair.ps1
```

It is intended to be run from the Windows machine controlling the two Linux VMs.

For example, the representative final configuration at a requested `200k msg/s` is:

```powershell
.\scripts\run_pair.ps1 -Rate 200000 -Samples 10000000 -Batching
```

For a run without batching:

```powershell
.\scripts\run_pair.ps1 -Rate 50000 -Samples 1000000
```

`-Rate` controls the Producer requested message rate and `-Samples` controls how many messages the Consumer measures.

### Benchmark sequence

`run_pair.ps1` performs the test in the following order:

1. records the pre-run clock/`chrony` state on both VMs;
2. records the checked-out Git commit and selected message profile;
3. starts the Receiver;
4. creates the Producer SHM and starts the Producer on Sender core `2`;
5. starts the Sender on Sender core `3`;
6. waits for a 5-second warm-up period;
7. starts the Consumer on Receiver core `2` with `--from-edge`;
8. waits until exactly the requested sample count is measured;
9. stops Producer, Sender and Receiver;
10. collects shutdown counters;
11. records the post-run clock state.

`--from-edge` is important because it excludes startup SHM backlog from the measured latency interval.

Each run receives an identifier of the form:

```text
<UTC timestamp>-r<rate>-n<samples>
```

Logs and measurement files are stored on the VMs under:

```text
/var/tmp/lldt-benchmark/<RUN-ID>/
```

The Receiver directory contains `latency.csv` with the per-message latency samples used by `analysis.ipynb` to generate the latency-distribution and percentile-tail plots.

### Plot generation

Raw `latency.csv` files are intentionally not committed to the repository because the larger benchmark runs produce very large files. The generated plots used in the submitted results are committed under `docs/benchmarks/`.

To regenerate plots for downloaded benchmark results, place each CSV under:

```text
benchmark-results/<RUN-ID>/latency.csv
```

and run:

```bash
./scripts/render_latency_plots.sh
```

The script processes every run under `benchmark-results/`. For each run it creates a temporary working directory, copies the corresponding CSV to the `data/latency.csv` path expected by `analysis.ipynb`, executes a temporary copy of the notebook, and exports:

```text
<RUN-ID>-distribution.png
<RUN-ID>-tail.png
```

into:

```text
docs/benchmarks/
```

The committed plots are linked directly from [E2E_RESULTS.md](E2E_RESULTS.md) and [E2E_OPTIMIZED_RESULTS.md](E2E_OPTIMIZED_RESULTS.md).

### Environment-specific values in `run_pair.ps1`

`run_pair.ps1` contains configuration for the benchmark environment used for the submitted measurements. These values are **not transport requirements**.

The current script has the following benchmark-machine values hardcoded:

```text
Sender SSH:       ubuntu@51.20.212.52
Receiver SSH:     ubuntu@51.21.142.26

Sender datapath:  10.0.1.10
Receiver datapath:10.0.1.20

Sender next-hop MAC:   06:cd:a3:3f:bc:bb
Receiver next-hop MAC: 06:76:72:0f:0d:89

SSH key:          $HOME\.ssh\lldt.pem
Repository path:  /home/ubuntu/projects/low-latency-data-transfer-challenge
```

To reproduce the benchmark on another pair of machines, update these values near the beginning of `scripts/run_pair.ps1`.

The transport launchers themselves are not tied to these addresses:

```text
scripts/run_sender.sh
scripts/run_receiver.sh
```

They receive the local IP, peer IP and next-hop MAC as command-line arguments.

---

## Benchmark results

The main benchmark was a four-way ablation:

```text
Raw     + Batching OFF
Raw     + Batching ON
Compact + Batching OFF
Compact + Batching ON
```

Full logs, DPDK/driver counters, clock snapshots and latency plots are available in:

- [E2E_RESULTS.md](E2E_RESULTS.md)

### Main observations

The experiments show that **packet rate rather than network bandwidth was the primary limitation of the initial datapath**.

With batching disabled, both Raw and Compact configurations saturated around `50k msg/s`. Compact messages alone do not help much in this mode because every source frame still requires one UDP packet and one TX submission.

Raw + batching substantially improved throughput:

- clean through `100k msg/s`;
- `0.1092%` Consumer drop rate at requested `200k msg/s`;
- clear saturation at requested `400k msg/s`, with `23.27%` Consumer loss.

Compact + batching was the strongest configuration.

At the representative requested rate of `200k msg/s`:

| Metric | Result |
|---|---:|
| Consumer drop rate | `0%` |
| p50 | `27.2 us` |
| p99 | `50.6 us` |
| p99.9 | `67.5 us` |
| p99.99 | `81.9 us` |
| Average source frames / Data packet | `5.75` |

At requested `400k msg/s`, Compact + batching reached approximately `6.65` source frames per Data packet while still showing no transport loss.

Across the meaningful Compact + batching sweep there were:

- no Sender source-SHM gaps;
- no TX-unsent packets;
- no Receiver missing Data packets;
- no Consumer drops.

### Producer ceiling

The supplied Producer became the limiting component before the Compact + batching transport saturated.

With Compact mixed messages and pacing disabled:

```text
16,000,000 messages / 23.10 s ~= 693,000 msg/s
```

Therefore approximately **700k msg/s** was the maximum generated load available on this benchmark machine.

Runs requested at `800k` and `1.6M msg/s` are retained in the results, but they must not be interpreted as proof that those offered rates were actually generated.

The measured transport ceiling for Compact + batching was therefore not reached with the current Producer.

---

## Rejected TX-burst experiment

After selecting Compact + batching, I also tested a bounded opportunistic multi-mbuf TX-burst variant of the Sender.

The implementation accumulated multiple already-ready packets and submitted them together when possible, without waiting for future source data.

Full measurements are available in:

- [E2E_OPTIMIZED_RESULTS.md](E2E_OPTIMIZED_RESULTS.md)

Several latency percentiles improved in this experiment. However, actual multi-packet bursts remained uncommon: the measured number of Data packets per `rte_eth_tx_burst()` call stayed close to `1` across the sweep.

At the same time, source-frame packing changed significantly compared with the baseline, and the `200k` run showed a small `0.0038%` source-side loss. This made it difficult to attribute the apparent latency improvement specifically to TX bursting.

The optimization was therefore **rejected rather than merged into the final datapath**.

The final Sender keeps the simpler:

```text
Compact + source-frame batching + single-packet TX submission
```

configuration.

Keeping this negative experiment in the repository is intentional: it documents an optimization that was implemented, measured, and rejected based on the resulting evidence rather than retained solely because it improved some benchmark numbers.

---

## Fan-out

The submitted implementation supports **one Sender -> one Receiver**. Multi-receiver fan-out was intentionally left outside the final implemented scope so that the baseline DPDK datapath could first be completed, measured, and optimized end-to-end.

The current architecture can be extended to a small number of receivers without changing the upstream Sender pipeline.

The intended software fan-out design would keep:

```text
Producer SHM
    -> SenderShmReader
    -> validation
    -> source-frame batching
    -> canonical LLDT Data packet
```

as a single shared path.

After a canonical LLDT Data packet has been constructed once, a fan-out stage would replicate it to a configured receiver set. Each receiver would have a precomputed destination descriptor containing its L2/L3 addressing information, while the source validation and batching work would not be repeated per receiver.

Conceptually:

```text
                         -> destination A -> DPDK TX
canonical Data packet ---+-> destination B -> DPDK TX
                         -> destination C -> DPDK TX
```

For the small fan-out sizes mentioned in the challenge (`1-3` receivers), direct software replication is the simplest extension. Destination-specific Ethernet/IP headers and mbuf ownership would belong to the fan-out/TX stage.

The LLDT `data_seq` can remain stream-global: all receivers observe the same logical Data-packet sequence, and the current Receiver already establishes its expected sequence from the first accepted packet. A later control plane could add dynamic receiver registration and membership management.

For substantially larger receiver counts, L2 multicast would also be worth evaluating where the deployment network supports it, because it can avoid linearly replicating packets in the Sender.

---

## Final configuration

The final submitted datapath prioritizes a small hot path and reduced packet rate:

```text
Compact source ABI
        +
opportunistic source-frame batching
        +
DPDK userspace UDP transport
        +
minimal RX parsing / direct SHM publication
```

The main performance gain came from reducing the number of network packets required for the market-data stream, rather than from adding additional buffering or retry machinery to the TX path.

The current submission is intentionally a minimal, measured unicast datapath. Multi-receiver fan-out, dynamic membership, and application-level retransmission/FEC are not implemented in the submitted version; the intended fan-out extension is described above.