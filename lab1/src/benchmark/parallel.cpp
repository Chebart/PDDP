#include <benchmark/benchmark.h>
#include "../utils.hpp"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <random>
#include <thread>
#include <vector>

static double simulate_ruin_par(const Config& cfg,
                                uint64_t seed,
                                size_t num_threads)
{
    const int chunk = (cfg.num_games + static_cast<int>(num_threads) - 1)
                      / static_cast<int>(num_threads);

    std::vector<int> local_ruined(num_threads, 0);
    std::vector<std::thread> threads;
    threads.reserve(num_threads);

    for (size_t t = 0; t < num_threads; ++t) {
        const int begin = static_cast<int>(t) * chunk;
        const int end   = std::min(begin + chunk, cfg.num_games);
        if (begin >= end) break;

        threads.emplace_back([&, t, begin, end]() {
            std::mt19937_64 rng(seed + t);
            std::bernoulli_distribution flip(cfg.win_prob);

            int ruined = 0;
            for (int g = begin; g < end; ++g) {
                int capital = cfg.initial_capital;
                while (capital > 0 && capital < cfg.target)
                    capital += flip(rng) ? 1 : -1;
                if (capital == 0) ++ruined;
            }
            local_ruined[t] = ruined;
        });
    }

    for (auto& th : threads) th.join();

    int total = 0;
    for (int r : local_ruined) total += r;
    return static_cast<double>(total) / cfg.num_games;
}

static void bench_parallel(benchmark::State& state)
{
    const size_t num_threads = static_cast<size_t>(state.range(0));
    const char* data_path = std::getenv("BENCH_PAR_DATA");
    const char* out_csv   = std::getenv("BENCH_OUTPUT_CSV");
    const auto configs = read_configs(data_path);

    int64_t total_games = 0;
    for (const auto& c : configs) total_games += c.num_games;

    std::vector<double> iter_us, gps;
    iter_us.reserve(state.max_iterations);
    gps.reserve(state.max_iterations);
    for (auto _ : state) {
        double result = 0.0;

        auto t0 = std::chrono::high_resolution_clock::now();
        for (size_t i = 0; i < configs.size(); ++i)
            result += simulate_ruin_par(configs[i], i, num_threads);
        auto t1 = std::chrono::high_resolution_clock::now();

        benchmark::DoNotOptimize(result);

        const double us  = std::chrono::duration<double, std::micro>(t1 - t0).count();
        state.SetIterationTime(us * 1e-6);
        iter_us.push_back(us);
        gps.push_back(static_cast<double>(total_games) / (us * 1e-6 + 1e-10));
    }

    write_csv(out_csv, "parallel", static_cast<int>(num_threads), iter_us, gps);
}

BENCHMARK(bench_parallel)
    ->Arg(2)->Arg(4)->Arg(8)->Arg(16)->Arg(32)->Arg(64)->Arg(128)
    ->UseManualTime()
    ->Iterations(150)
    ->Unit(benchmark::kMicrosecond)
    ->Name("bench_parallel");
