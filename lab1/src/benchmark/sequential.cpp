#include <benchmark/benchmark.h>
#include "../utils.hpp"

#include <chrono>
#include <cstdlib>
#include <random>
#include <vector>

static double simulate_ruin_seq(const Config& cfg, uint64_t seed)
{
    std::mt19937_64 rng(seed);
    std::bernoulli_distribution flip(cfg.win_prob);

    int ruined = 0;
    for (int g = 0; g < cfg.num_games; ++g) {
        int capital = cfg.initial_capital;
        while (capital > 0 && capital < cfg.target)
            capital += flip(rng) ? 1 : -1;
        if (capital == 0) ++ruined;
    }
    return static_cast<double>(ruined) / cfg.num_games;
}

static void bench_sequential(benchmark::State& state)
{
    const char* data_path = std::getenv("BENCH_SEQ_DATA");
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
            result += simulate_ruin_seq(configs[i], i);
        auto t1 = std::chrono::high_resolution_clock::now();

        benchmark::DoNotOptimize(result);

        const double us  = std::chrono::duration<double, std::micro>(t1 - t0).count();
        state.SetIterationTime(us * 1e-6);
        iter_us.push_back(us);
        gps.push_back(static_cast<double>(total_games) / (us * 1e-6 + 1e-10));
    }

    write_csv(out_csv, "sequential", 1, iter_us, gps);
}

BENCHMARK(bench_sequential)
    ->UseManualTime()
    ->Iterations(150)
    ->Unit(benchmark::kMicrosecond)
    ->Name("bench_sequential");
