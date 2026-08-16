# Organizer's notes on the baseline solution

🇷🇺 [Русская версия](baseline_solution.md)

These are the organizers' notes about how the baseline solution in the repository located at [agent solution](https://gitlab.spectral.tech/challenge/agent-solution) was
produced, and on what hardware it was measured.

## How this solution was produced

The solution was written by a Claude agent working **almost entirely autonomously**.

**It had no information about the task beyond what this repository contains**. There was
no reference implementation, no description of an intended solution, and no hints about
which approach we consider correct. The agent read the same task statement and the same
harness that every participant received, and made its own decisions from there.

A human operator was involved in the following cases:

- **Access to the machines**, together with safety constraints for them.
- **Publication rules** — what may appear in a public repository and what must stay out of it (internal hostnames, for example).
- **Basic sanity checks at checkpoints**.

Everything else — the transport design, all of the code, the measurement methodology,
running the benchmarks, diagnosing what the results meant, and the write-up — is the
agent's own work.

Several corrections it found by itself are worth noting:

- Writing one sample per message to a file from inside the measurement loop inflated p99.99 by roughly two orders of magnitude. It found this by comparing the same configuration written to disk, to tmpfs, and not at all.
- Two spinning threads sharing one isolated core produce latency quantised to the scheduler timeslice, which looks exactly like a network problem. `isolcpus` prevents the scheduler from *migrating* work onto a core but not from running work pinned there. The agent turned this into a preflight check that refuses to measure on a contended core, and that check later caught a stray process left from previous runs.
- Its fan-out sweep initially showed one receiver as *slower* than two, which is impossible. The cause was that its own redundancy mechanism adapts to load, so receiver count and redundancy were varying together.
- Its first choice of system call for replicating a datagram to several destinations was based on a structural argument that turned out to be wrong when measured on a real NIC, and it reversed the decision.

## Test environment

Two hosts, both in a **single VPC and the same subnet**, with direct layer-2
connectivity between them (no router hop on the measured path), and both in the same
availability zone.

| | |
|---|---|
| Sending host | `m7i.metal-24xl` (bare metal) |
| Receiving host | `m7i.24xlarge` (virtualised) |
| OS | Ubuntu 20.04 LTS |
| Kernel | Linux 6.9 |
| CPU | Intel Xeon Platinum 8488C, SMT disabled — 48 online cores |
| Topology | single NUMA node |
| NIC | ENA adapter, MTU 1500, verified end to end with a no-fragment probe |
| Receivers | up to 10 independent receivers, each with its own socket and its own consumer |

**Host tuning.** The kernel on both machines was configured for low latency:

- Cores isolated from the scheduler, with a set of housekeeping cores left outside the isolated range.
- NIC interrupts pinned to the housekeeping cores, so device interrupts never preempt a spinning measurement thread.

The solution did not change NIC settings such as interrupt coalescing. After the initial setup everything it tuned is inside its own processes: which core each one runs on, and how it uses its sockets.

**Clock synchronisation.** The hosts were synchronised by chrony to well within 3 microseconds; the offset measured during the runs was a few hundred nanoseconds. PTP and other synchronization methods with more precision are left as possible improvements by the agent.

## What this means for the numbers

- **This is a baseline, not a end-goal solution.** It is a working solution with its analysis
  written down honestly, including what it fails to establish. The write-up lists its
  own open items, the largest being that the far tail is dominated by a recurring event
  it attributes to the kernel network path but does not isolate further.
- **Its measurement methodology is probably more reusable than its transport.** The
  traps it documents — file I/O on the measurement path, contended isolated cores,
  runs too short for the percentile being quoted, configurations compared in blocks
  rather than interleaved — will cost time for anyone who does not know about them.

Participants are free to use any of this as a starting point, to disagree with its
design decisions, and to beat it.
