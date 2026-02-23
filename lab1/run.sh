#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
BENCH="${BUILD_DIR}/bin/lab1"
RESULTS_DIR="${ROOT_DIR}/results"
PLOTS_DIR="${ROOT_DIR}/plots"

# Generate data files if absent
if [ ! -f "${ROOT_DIR}/data/same_data.bin" ] || \
   [ ! -f "${ROOT_DIR}/data/seq_data.bin" ] || \
   [ ! -f "${ROOT_DIR}/data/parallel_data.bin" ]; then
    echo "==> Generating data files..."
    python3 "${ROOT_DIR}/data/generate_data.py"
fi

# Build
echo "==> Building..."
cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" -j"$(nproc)"
mkdir -p "${RESULTS_DIR}" "${PLOTS_DIR}"

# Clean old results
rm -f "${RESULTS_DIR}"/*.csv
rm -f "${PLOTS_DIR}"/*.png

# Experiment 1: same data (seq and par read the same file)
echo "==> [1/2] Benchmark on same data..."
export BENCH_SEQ_DATA="${ROOT_DIR}/data/same_data.bin"
export BENCH_PAR_DATA="${ROOT_DIR}/data/same_data.bin"
export BENCH_OUTPUT_CSV="${RESULTS_DIR}/same_data.csv"
"${BENCH}" --benchmark_filter="bench_sequential|bench_parallel" --benchmark_format=console

# Experiment 2: different data (seq and par read different files)
echo "==> [2/2] Benchmark on different data..."
export BENCH_SEQ_DATA="${ROOT_DIR}/data/seq_data.bin"
export BENCH_PAR_DATA="${ROOT_DIR}/data/parallel_data.bin"
export BENCH_OUTPUT_CSV="${RESULTS_DIR}/diff_data.csv"
"${BENCH}" --benchmark_filter="bench_sequential|bench_parallel" --benchmark_format=console

# Draw plots
if command -v python3 >/dev/null 2>&1; then
    echo "==> Drawing plots..."
    python3 "${ROOT_DIR}/draw_plots.py" --results "${RESULTS_DIR}" --out "${PLOTS_DIR}"
fi
