/*
 * Compact market-data messages for the LLDT fan-out harness.
 *
 * Author: ChatGPT 5.6 Sol
 *
 * This schema is an optimized revision of the Compact message format from the
 * agent baseline solution.  It keeps the baseline's important properties:
 *
 *   - seq_id and send_ts_ns remain uint64_t at offsets 0 and 8;
 *   - symbol/venue/currency strings are replaced by an instrument identifier;
 *   - prices and quantities use exact fixed-point integer representations;
 *   - BBO ask price and deeper book prices use intra-frame offsets;
 *   - Trade keeps cumulative values so aggregate state can recover after loss;
 *   - BBO and OrderBook remain self-contained snapshots;
 *   - no field depends on a previously received frame.
 *
 * Relative to the agent baseline layout, this version makes the following
 * additional reductions:
 *
 *   - Header:    32 -> 24 bytes.  The current harness generates identical
 *                exchange and match-engine timestamps, so only one signed
 *                delta from send_ts_ns is retained; body length is implied by
 *                type and protocol versioning belongs to the LLDT envelope.
 *   - Trade:     80 -> 64 bytes.  Price and per-trade quantity are narrowed to
 *                uint32_t while the independent trade id and all cumulative
 *                counters remain uint64_t.
 *   - Bbo:       64 -> 48 bytes.  Bid price is uint32_t; spread, quantities,
 *                and order counts are uint16_t.
 *   - OrderBook: 160 -> 96 bytes.  Each 5-level side is 32 bytes: one uint32_t
 *                top price followed by uint16_t price offsets, quantities,
 *                and order counts.  update_id is retained.  prev_update_id is
 *                redundant with source sequencing in the current harness, and
 *                the original synthetic checksum was derived from seq_id
 *                rather than from snapshot contents, so neither is carried.
 *
 * The chosen ranges are specific to the supplied BTCUSDT harness profile:
 * uint32_t price ticks at 0.01 cover prices up to 42,949,672.95;
 * uint16_t quantity lots at 0.001 cover 65.535 BTC per BBO/book level; and
 * uint16_t price offsets at 0.01 cover 655.35 away from the side's top level.
 * Trade quantity remains uint32_t because doing so costs no additional space.
 *
 * These structures are the source ABI of the Compact profile.  Producer must
 * construct them directly; Sender and Receiver transport their bytes without
 * Compact <-> Raw conversion.  Deliberate cache-line alignment is left to SHM
 * slots and working buffers: alignas(64) on these wire records would round up
 * their transmitted and copied sizes and erase much of the benefit.
 */
#pragma once

#include <cstddef>
#include <cstdint>

namespace msg {

inline constexpr std::uint32_t kBookDepth = 5;
inline constexpr std::uint8_t kCodecId = 2;
inline constexpr char kProfileName[] = "compact";

enum class Type : std::uint8_t {
  Trade = 1,
  Bbo = 2,
  OrderBook = 3,
};

// Static reference data.  The wire records carry only the array index.
struct Instrument {
  const char* symbol;
  const char* venue;
  const char* base_currency;
  const char* quote_currency;
};

inline constexpr Instrument kInstruments[] = {
    {"BTCUSDT", "BINANCE", "BTC", "USDT"},
};

inline constexpr std::uint16_t kInstrumentCount =
    static_cast<std::uint16_t>(sizeof(kInstruments) / sizeof(kInstruments[0]));
inline constexpr std::uint16_t kBtcUsdtInstrument = 0;

// Fixed-point scales used by this profile.
inline constexpr std::uint32_t kPriceScale = 100;
inline constexpr std::uint32_t kQuantityScale = 1000;
inline constexpr double kPriceTickSize = 1.0 / kPriceScale;
inline constexpr double kQtyLotSize = 1.0 / kQuantityScale;

// Header::flags.  The interpretation of a bit is restricted to the message
// types for which it is meaningful.  Bit 7 remains reserved and must be zero.
inline constexpr std::uint8_t kFlagAggressorSell = 1u << 0;
inline constexpr std::uint8_t kFlagBlockTrade = 1u << 1;
inline constexpr std::uint8_t kFlagRpi = 1u << 2;
inline constexpr std::uint8_t kFlagLiquidation = 1u << 3;
inline constexpr std::uint8_t kFlagSnapshot = 1u << 4;
inline constexpr std::uint8_t kTickDirectionShift = 5;
inline constexpr std::uint8_t kTickDirectionMask = 0x3u << kTickDirectionShift;

// Common prefix of every Compact frame.
struct Header {
  // Fixed harness contract: do not change these fields or their offsets.
  std::uint64_t seq_id;
  std::uint64_t send_ts_ns;

  std::uint16_t instrument;  // index into kInstruments
  std::uint8_t type;         // msg::Type
  std::uint8_t flags;        // kFlag* values above

  // send_ts_ns - exchange_ts_ns.  A signed value tolerates a small negative
  // delta caused by clock adjustment while keeping each frame self-contained.
  std::int32_t exchange_ts_delta_ns;
};

struct Trade {
  Header header;

  std::uint64_t trade_id;
  std::uint32_t price_ticks;
  std::uint32_t quantity_lots;

  // Running aggregates over Trade frames.  The notional unit is one
  // price-tick multiplied by one quantity-lot.
  std::uint64_t cumulative_quantity_lots;
  std::uint64_t cumulative_notional_tick_lots;
  std::uint64_t cumulative_trade_count;
};

struct Bbo {
  Header header;

  std::uint64_t update_id;
  std::uint32_t bid_price_ticks;
  std::uint16_t spread_ticks;  // ask_price_ticks = bid + spread
  std::uint16_t bid_size_lots;
  std::uint16_t ask_size_lots;
  std::uint16_t bid_order_count;
  std::uint16_t ask_order_count;
  std::uint16_t reserved;      // must be zero; occupies otherwise-tail padding
};

// One self-contained side of a five-level book.  price_offset_ticks[0]
// describes level 1 relative to top_price_ticks, and so on through level 4.
// Bid prices subtract the positive offset; ask prices add it.
struct Side {
  std::uint32_t top_price_ticks;
  std::uint16_t price_offset_ticks[kBookDepth - 1];
  std::uint16_t size_lots[kBookDepth];
  std::uint16_t order_count[kBookDepth];
};

struct OrderBook {
  Header header;

  std::uint64_t update_id;
  Side bids;
  Side asks;
};

constexpr std::uint32_t frame_size(const Type type) noexcept {
  switch (type) {
    case Type::Trade:
      return sizeof(Trade);
    case Type::Bbo:
      return sizeof(Bbo);
    case Type::OrderBook:
      return sizeof(OrderBook);
  }
  return 0;
}

constexpr std::uint32_t frame_size(const Header& header) noexcept {
  return frame_size(static_cast<Type>(header.type));
}

constexpr std::uint64_t exchange_ts_ns(const Header& header) noexcept {
  if (header.exchange_ts_delta_ns >= 0) {
    return header.send_ts_ns -
           static_cast<std::uint32_t>(header.exchange_ts_delta_ns);
  }

  return header.send_ts_ns + static_cast<std::uint32_t>(
                                 -static_cast<std::int64_t>(
                                     header.exchange_ts_delta_ns));
}

inline constexpr std::uint32_t kMaxFrame = sizeof(OrderBook);

// Exact sizes and prefix offsets are part of codec_id=2.  They also determine
// SHM slot size and the Receiver's boundaries between batched records.
static_assert(sizeof(Header) == 24, "Compact Header ABI changed");
static_assert(offsetof(Header, seq_id) == 0,
              "Compact Header::seq_id offset changed");
static_assert(offsetof(Header, send_ts_ns) == 8,
              "Compact Header::send_ts_ns offset changed");
static_assert(sizeof(Trade) == 64, "Compact Trade ABI changed");
static_assert(sizeof(Bbo) == 48, "Compact Bbo ABI changed");
static_assert(sizeof(Side) == 32, "Compact Side ABI changed");
static_assert(sizeof(OrderBook) == 96, "Compact OrderBook ABI changed");

static_assert(sizeof(Trade) <= kMaxFrame,
              "kMaxFrame must fit every Compact message");
static_assert(sizeof(Bbo) <= kMaxFrame,
              "kMaxFrame must fit every Compact message");

}  // namespace msg