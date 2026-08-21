#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <vector>


namespace metrics
{
    struct Report
    {
        std::uint64_t received{};
        std::uint64_t expected{};
        std::uint64_t dropped{};
        double drop_rate{};

        std::uint64_t overflow{};

        std::uint64_t lat_min{};
        std::uint64_t lat_max{};
        double lat_mean{};

        std::uint64_t p01{};
        std::uint64_t p50{};
        std::uint64_t p99{};
        std::uint64_t p999{};
        std::uint64_t p9999{};
    };

    struct Sample
    {
        std::uint64_t seq_id;
        std::uint64_t latency_ns;
    };

    class Accumulator
    {
    public:
        explicit Accumulator(std::size_t capacity = 1u << 20)
            : samples_(capacity)
        {
            touch_pages();
        }

        void record(
            std::uint64_t seq_id,
            std::uint64_t latency_ns) noexcept
        {
            if (received_ == 0)
            {
                first_seq_ = seq_id;
                last_seq_ = seq_id;
            }
            else
            {
                if (seq_id < first_seq_)
                    first_seq_ = seq_id;

                if (seq_id > last_seq_)
                    last_seq_ = seq_id;
            }

            ++received_;

            if (stored_ == samples_.size())
            {
                ++overflow_;
                return;
            }

            samples_[stored_++] = Sample{
                seq_id,
                latency_ns
            };
        }

        [[nodiscard]] std::uint64_t overflow() const noexcept
        {
            return overflow_;
        }

        [[nodiscard]] std::size_t stored() const noexcept
        {
            return stored_;
        }

        [[nodiscard]] Report report() const
        {
            Report result{};

            result.received = received_;
            result.overflow = overflow_;

            if (received_ == 0)
                return result;

            result.expected = last_seq_ - first_seq_ + 1;
            result.dropped =
                result.expected > result.received
                    ? result.expected - result.received
                    : 0;

            result.drop_rate =
                result.expected != 0
                    ? static_cast<double>(result.dropped) /
                        static_cast<double>(result.expected)
                    : 0.0;

            if (stored_ == 0)
                return result;

            std::vector<std::uint64_t> latencies(stored_);

            long double sum = 0.0;

            for (std::size_t i = 0; i < stored_; ++i)
            {
                latencies[i] = samples_[i].latency_ns;
                sum += static_cast<long double>(samples_[i].latency_ns);
            }

            std::sort(latencies.begin(), latencies.end());

            result.lat_min = latencies.front();
            result.lat_max = latencies.back();
            result.lat_mean =
                static_cast<double>(
                    sum / static_cast<long double>(stored_));

            result.p01 = percentile(latencies, 0.01);
            result.p50 = percentile(latencies, 0.50);
            result.p99 = percentile(latencies, 0.99);
            result.p999 = percentile(latencies, 0.999);
            result.p9999 = percentile(latencies, 0.9999);

            return result;
        }

        [[nodiscard]] bool dump_csv(const char* path) const
        {
            FILE* file = std::fopen(path, "w");

            if (file == nullptr)
                return false;

            std::fprintf(file, "seq,latency_ns\n");

            for (std::size_t i = 0; i < stored_; ++i)
            {
                std::fprintf(
                    file,
                    "%llu,%llu\n",
                    static_cast<unsigned long long>(samples_[i].seq_id),
                    static_cast<unsigned long long>(samples_[i].latency_ns));
            }

            return std::fclose(file) == 0;
        }

    private:
        static std::uint64_t percentile(
            const std::vector<std::uint64_t>& sorted,
            double p) noexcept
        {
            if (sorted.empty())
                return 0;

            const std::size_t n = sorted.size();
            const double exact_rank = p * static_cast<double>(n);

            std::size_t rank = static_cast<std::size_t>(exact_rank);

            if (static_cast<double>(rank) < exact_rank)
                ++rank;

            if (rank < 1)
                rank = 1;

            if (rank > n)
                rank = n;

            return sorted[rank - 1];
        }

        void touch_pages() noexcept
        {
            if (samples_.empty())
                return;

            constexpr std::size_t PAGE_SIZE = 4096;

            volatile std::uint8_t* bytes =
                reinterpret_cast<volatile std::uint8_t*>(
                    samples_.data());

            const std::size_t size =
                samples_.size() * sizeof(Sample);

            for (std::size_t offset = 0;
                 offset < size;
                 offset += PAGE_SIZE)
            {
                bytes[offset] = bytes[offset];
            }

            bytes[size - 1] = bytes[size - 1];
        }

        std::vector<Sample> samples_;

        std::size_t stored_{};

        std::uint64_t overflow_{};
        std::uint64_t received_{};
        std::uint64_t first_seq_{};
        std::uint64_t last_seq_{};
    };

} // namespace metrics