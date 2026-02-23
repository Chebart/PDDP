#include "utils.hpp"
#include <fstream>
#include <stdexcept>

std::vector<Config> read_configs(const std::string& path)
{
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("Cannot open: " + path);

    int64_t n = 0;
    f.read(reinterpret_cast<char*>(&n), sizeof(n));

    std::vector<Config> configs(static_cast<size_t>(n));
    f.read(reinterpret_cast<char*>(configs.data()), n * sizeof(Config));
    return configs;
}

void write_csv(const std::string& path,
               const std::string& inst_type,
               int num_threads,
               const std::vector<double>& iter_us,
               const std::vector<double>& games_per_sec)
{
    bool need_header = false;
    {
        std::ifstream check(path);
        need_header = !check.good() ||
                      check.peek() == std::ifstream::traits_type::eof();
    }

    std::ofstream f(path, std::ios::app);
    if (!f) return;

    if (need_header)
        f << "inst_type,num_threads,duration_us,games_per_sec\n";

    for (size_t i = 0; i < iter_us.size(); ++i)
        f << inst_type << ',' << num_threads << ','
          << iter_us[i] << ',' << games_per_sec[i] << '\n';
}
