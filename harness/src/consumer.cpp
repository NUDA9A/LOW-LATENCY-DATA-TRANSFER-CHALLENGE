#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "message.h"
#include "metrics.h"
#include "shm_ring.h"
#include "shm_segment.h"
#include "util.h"


namespace
{
    constexpr std::size_t DEFAULT_SAMPLE_CAPACITY = 1u << 22;

    static_assert(offsetof(msg::Header, seq_id) == 0);
    static_assert(offsetof(msg::Header, send_ts_ns) == 8);

    struct Config
    {
        std::string shm_name = "/fanout_ring";
        std::uint32_t slots = 1024;
        std::uint64_t count = 0;
        bool from_edge = false;
        std::string csv;
        std::uint64_t idle_ms = 2000;
    };

    struct Framing
    {
        std::uint64_t seq_id;
        std::uint64_t send_ts_ns;
    };

    Framing load_framing(const std::uint8_t* frame) noexcept
    {
        Framing framing{};

        std::memcpy(
            &framing.seq_id,
            frame + offsetof(msg::Header, seq_id),
            sizeof(framing.seq_id));

        std::memcpy(
            &framing.send_ts_ns,
            frame + offsetof(msg::Header, send_ts_ns),
            sizeof(framing.send_ts_ns));

        return framing;
    }

    Config parse_args(int argc, char** argv)
    {
        Config config{};

        for (int i = 1; i < argc; ++i)
        {
            std::string argument = argv[i];

            auto next = [&]() -> std::string
            {
                if (i + 1 >= argc)
                {
                    std::fprintf(
                        stderr,
                        "missing value for %s\n",
                        argument.c_str());

                    std::exit(2);
                }

                return argv[++i];
            };

            if (argument == "--shm")
                config.shm_name = next();
            else if (argument == "--slots")
                config.slots =
                    static_cast<std::uint32_t>(
                        std::stoul(next()));
            else if (argument == "--count")
                config.count = std::stoull(next());
            else if (argument == "--from-edge")
                config.from_edge = true;
            else if (argument == "--csv")
                config.csv = next();
            else if (argument == "--idle-ms")
                config.idle_ms = std::stoull(next());
            else
            {
                std::fprintf(
                    stderr,
                    "unknown arg: %s\n",
                    argument.c_str());

                std::exit(2);
            }
        }

        return config;
    }

    void print_report(const metrics::Report& report)
    {
        std::printf("---- delivery metrics ----\n");
        std::printf(
            "received     : %llu\n",
            static_cast<unsigned long long>(report.received));
        std::printf(
            "expected     : %llu\n",
            static_cast<unsigned long long>(report.expected));
        std::printf(
            "dropped      : %llu\n",
            static_cast<unsigned long long>(report.dropped));
        std::printf(
            "drop_rate    : %.4f%%\n",
            report.drop_rate * 100.0);

        if (report.overflow != 0)
        {
            std::printf(
                "NOT STORED   : %llu\n",
                static_cast<unsigned long long>(report.overflow));
        }

        std::printf(
            "latency (ns) : min=%llu mean=%.0f max=%llu\n",
            static_cast<unsigned long long>(report.lat_min),
            report.lat_mean,
            static_cast<unsigned long long>(report.lat_max));

        std::printf(
            "  p01        : %llu\n",
            static_cast<unsigned long long>(report.p01));
        std::printf(
            "  p50        : %llu\n",
            static_cast<unsigned long long>(report.p50));
        std::printf(
            "  p99        : %llu\n",
            static_cast<unsigned long long>(report.p99));
        std::printf(
            "  p99.9      : %llu\n",
            static_cast<unsigned long long>(report.p999));
        std::printf(
            "  p99.99     : %llu\n",
            static_cast<unsigned long long>(report.p9999));
    }

} // namespace


int main(int argc, char** argv)
{
    const Config config = parse_args(argc, argv);

    shm::Segment segment =
        shm::Segment::open(
            config.shm_name,
            shm::region_size(config.slots),
            false);

    shm::Ring ring;
    ring.attach(segment.base(), config.slots, false);

    const std::size_t sample_capacity =
        config.count != 0
            ? static_cast<std::size_t>(config.count)
            : DEFAULT_SAMPLE_CAPACITY;

    metrics::Accumulator accumulator{sample_capacity};

    std::uint64_t read_index =
        config.from_edge
            ? ring.live_edge()
            : 0;

    std::uint64_t received{};
    std::uint64_t lapped_events{};

    const std::uint64_t idle_ns =
        config.idle_ms * 1'000'000ull;

    std::uint64_t last_progress = util::now_ns();

    alignas(64) std::uint8_t frame[shm::kFrameCap];

    while (config.count == 0 || received < config.count)
    {
        std::uint32_t length{};
        std::uint64_t resume{};

        const auto status =
            ring.read(
                read_index,
                frame,
                &length,
                &resume);

        if (status == shm::Ring::FrameStatus::kOk)
        {
            const std::uint64_t receive_timestamp =
                util::now_ns();

            const Framing framing = load_framing(frame);

            const std::uint64_t latency =
                receive_timestamp > framing.send_ts_ns
                    ? receive_timestamp - framing.send_ts_ns
                    : 0;

            accumulator.record(
                framing.seq_id,
                latency);

            ++received;
            ++read_index;

            last_progress = receive_timestamp;
        }
        else if (status == shm::Ring::FrameStatus::kLapped)
        {
            ++lapped_events;
            read_index = resume;
        }
        else
        {
            if (util::now_ns() - last_progress > idle_ns)
                break;
        }
    }

    std::fprintf(
        stderr,
        "consumer: lapped %llu times\n",
        static_cast<unsigned long long>(lapped_events));

    const metrics::Report report = accumulator.report();
    print_report(report);

    if (!config.csv.empty() &&
        !accumulator.dump_csv(config.csv.c_str()))
    {
        std::fprintf(
            stderr,
            "consumer: failed to write %s\n",
            config.csv.c_str());

        return 1;
    }

    if (accumulator.overflow() != 0)
    {
        std::fprintf(
            stderr,
            "consumer: sample buffer overflow; percentile result is incomplete\n");

        return 1;
    }

    return 0;
}