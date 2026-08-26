# LLDT Wire Protocol


## 1. Baseline

- Protocol version: `1`.
- Transport multi-byte fields use network byte order (big-endian).
- Wire bytes MUST NOT depend on C++ struct layout, padding, ABI, or host endianness.
- Baseline Ethernet MTU is `1500`.
- IPv4 fragmentation and source-frame fragmentation are not used.
- The complete LLDT canonical image is the UDP payload and MUST NOT exceed `1472` bytes.
- The current protocol carries only Data packets. There is no packet-type field, control channel, FEC, NACK, retransmission, JOIN, or heartbeat traffic.

## 2. Common prefix v1

The common prefix is exactly **7 bytes**.

| Offset | Size | Field | Encoding |
|---:|---:|---|---|
| 0 | 4 | `magic` | ASCII bytes `LLDT` (`4c 4c 44 54`) |
| 4 | 1 | `protocol_version` | `1` |
| 5 | 2 | `header_length` | Unsigned big-endian byte length of the complete LLDT Data header; currently `22` (`00 16`) |

The prefix deliberately contains no packet type because the current protocol has only one wire packet kind.

## 3. Data v1 header

The Data v1 header is exactly **22 bytes**.

| Offset | Size | Field | Meaning |
|---:|---:|---|---|
| 0 | 4 | `magic` | `LLDT` |
| 4 | 1 | `protocol_version` | `1` |
| 5 | 2 | `header_length` | `22` |
| 7 | 8 | `data_seq` | Sender-owned monotonically increasing Data-packet sequence |
| 15 | 2 | `record_count` | Number of complete source frames concatenated in the payload |
| 17 | 5 | reserved padding | Sender writes zero; Receiver ignores these bytes |
| 22 | ... | payload | Byte-exact concatenation of source frames from the selected compile-time message profile |

## 4. Padding and payload placement

The five reserved bytes are layout padding, not semantic protocol state.

With the current fixed outer envelope:

- Ethernet II header: `14` bytes;
- IPv4 header without options: `20` bytes;
- UDP header: `8` bytes;
- LLDT Data header: `22` bytes.

Therefore the first source-frame byte begins at byte **64** relative to the start of the Ethernet frame:

```text
14 + 20 + 8 + 22 = 64
```

This preserves a cache-friendly payload placement while keeping the semantic header minimal. Sender MUST write the reserved bytes as zero. Receiver is not required to validate them.

The maximum source-frame payload carried by one UDP datagram is:

```text
1472 - 22 = 1450 bytes
```

## 5. Data sequence semantics

`data_seq` is independent of source `msg::Header::seq_id`.

- Sender initializes `data_seq` to `0` for a process run.
- Sender loop is the sole owner of `next_data_seq`.
- One finalized Data packet consumes exactly one `data_seq` value.
- A TX enqueue failure does not roll the sequence back.
- One Data packet may contain multiple source frames, so Data and source sequences are not 1:1.

There is no wire session identifier. One benchmark/pipeline run is one transport epoch. Seamless Sender restart inside an active Receiver run is not supported; restart the pipeline/Receiver when restarting Sender.

Receiver establishes its initial expected Data sequence from the first accepted packet. Thereafter:

- `data_seq == next_data_seq`: accept;
- `data_seq > next_data_seq`: count a forward gap and accept immediately;
- `data_seq < next_data_seq`: drop as stale/duplicate/late.

After acceptance, `next_data_seq = data_seq + 1`.

There is no reorder buffer, recovery wait, retransmission, or FEC in the current protocol.

## 6. Record payload

The Data payload is a concatenation of **complete** source frames. A source frame is never split between Data packets.

`record_count` is the number of concatenated frames and is always at least one for packets emitted by the current Sender.

### 6.1. Raw profile

Raw frames are copied byte-for-byte from the admitted source frame.

Current sizes:

| Frame | Size |
|---|---:|
| `msg::Header` | 24 |
| `Trade` | 192 |
| `Bbo` | 192 |
| `OrderBook` | 576 |

Raw frame length is provided by `msg::frame_size(header)`, which maps to the Raw `body_len` contract.

### 6.2. Compact profile

Compact frames are also transported byte-for-byte. The producer constructs the Compact representation directly; LLDT does not encode Raw into Compact or decode Compact into Raw.

Current sizes:

| Frame | Size |
|---|---:|
| `msg::Header` | 24 |
| `Trade` | 64 |
| `Bbo` | 48 |
| `OrderBook` | 96 |

Compact frame length is derived from `msg::Header::type` through `msg::frame_size()`.

### 6.3. Profile identity

Raw and Compact are separate **compile-time build profiles**. There is no runtime `codec_id` on the network and no runtime codec dispatch.

Build/orchestration is responsible for running matching producer/Sender/Receiver/consumer binaries. A Raw/Compact mismatch is a run-configuration error, not a condition handled by the Data hot path.

## 7. Batching contract

Sender may place multiple already-available complete source frames into one Data packet.

- Sender never waits for a future source frame to enlarge a batch.
- Batching may be disabled for ablation.
- The batch closes when the next frame does not fit, SHM has no immediately available frame, a source gap boundary is observed, shutdown is latched, or batching is disabled.
- A source gap boundary is not crossed inside one batch.
- `record_count` matches the number of frames actually copied into the packet.

## 8. Canonical image and outer envelope

The canonical LLDT image is exactly the UDP payload, beginning with byte 0 of
the LLDT header and ending with the final byte of the final source frame.

The DPDK transport materializes it inside a fixed outer envelope:

- Ethernet II;
- IPv4 without options, with DF set by the Sender;
- UDP.

Ethernet, IPv4 and UDP headers are not part of LLDT offsets or Data sequence
semantics.

The Sender MUST write correct outer length fields and a valid IPv4 header
checksum. The current implementation computes the IPv4 header checksum in
software and does not request checksum TX offloads.

For the current IPv4 transport the UDP checksum field is exactly `0x0000`. In
IPv4 this explicitly means that the UDP checksum is not used. Receiver does not
recompute or validate IPv4/UDP checksums and does not depend on PMD checksum
metadata.

The fixed 14-byte Ethernet + 20-byte IPv4 + 8-byte UDP shape remains a deployment
contract because Receiver locates the LLDT image at Ethernet offset `42`.

## 9. Validation and ownership

### Sender side

- `SenderShmReader` is the sole owner of source SHM framing validation,
  consistent-copy admission, source continuity classification and lapping
  handling.
- Downstream Sender components trust `ValidatedSourceFrameView` and do not
  repeat source framing validation.
- `RawDataPacketBuilder` owns batch-fit accounting, `record_count`, explicit
  LLDT serialization and canonical packet size.
- Sender loop alone owns `next_data_seq`, batching/carry state, mbuf TX ownership
  and shutdown state.
- DPDK materialization owns the complete Ethernet/IPv4/UDP frame, including
  software IPv4 header checksum and zero UDP checksum.

### Receiver side

The first E2E topology uses our own statically configured Sender as the expected
source. Receiver therefore performs deliberately minimal admission rather than
adversarial network-protocol validation.

- RX admission requires at least `64` contiguous bytes in the first mbuf segment;
- LLDT canonical bytes are addressed at fixed Ethernet offset `42`;
- parser validates only the 7-byte `magic/version/header_length` prefix, then
  alignment-safely decodes `data_seq` and `record_count`;
- Receiver does not validate Ethernet type, IPv4 fields, UDP ports or checksum
  metadata in the current controlled baseline;
- `ReceiverShmWriter` trusts the matched Sender/profile handoff and uses
  `msg::frame_size()` to walk `record_count` frames directly from the RX mbuf
  before publication;
- consumer remains the final owner of official source-sequence gap observation.

Additional defensive validation is added only if the deployment/trust model
changes or measurements show a concrete need.
