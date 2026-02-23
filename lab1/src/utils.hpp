#pragma once
#include <cstdint>
#include <string>
#include <vector>

// Simulation parameters for one Gambler's Ruin experiment.
// Layout: 16 bytes, no padding (all fields are 4 bytes).
struct Config {
    int32_t initial_capital;  // k: starting capital
    float   win_prob;         // p: probability of winning one round
    int32_t target;           // N: game ends when capital reaches 0 or N
    int32_t num_games;        // M: Monte Carlo games to simulate
};

// Binary format: int64_t (config count) + Config array.
std::vector<Config> read_configs(const std::string& path);

// Append rows to a scaling CSV.
// Columns: inst_type, num_threads, duration_us, games_per_sec
// Header is written automatically if the file is empty/new.
void write_csv(const std::string& path,
               const std::string& inst_type,
               int num_threads,
               const std::vector<double>& iter_us,
               const std::vector<double>& games_per_sec);
