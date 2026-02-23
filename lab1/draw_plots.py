import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def _clip(s: pd.Series, lo: float = 0.01, hi: float = 0.99) -> pd.Series:
    low, high = s.quantile([lo, hi])
    return s[(s >= low) & (s <= high)]


def make_plots(csv_path: Path, out_dir: str, prefix: str) -> None:
    df = pd.read_csv(csv_path)

    seq_mean = _clip(df[df["inst_type"] == "sequential"]["duration_us"]).mean() / 1e6

    par_df = df[df["inst_type"] == "parallel"].copy()
    par_df["duration_s"] = par_df["duration_us"] / 1e6
    grp = (
        par_df.groupby("num_threads")["duration_s"]
        .apply(_clip)
        .reset_index(level=0)
        .groupby("num_threads")["duration_s"]
        .agg(mean="mean", std="std")
        .reset_index()
    )
    grp["speedup"]    = seq_mean / grp["mean"]
    grp["efficiency"] = grp["speedup"] / grp["num_threads"]
    threads = grp["num_threads"].values

    # mean execution time bar chart
    fig, ax = plt.subplots(figsize=(10, 6))
    sns.barplot(
        x="num_threads", y="mean",
        data=grp, color="steelblue",
        errorbar=None, ax=ax,
    )
    ax.axhline(seq_mean, color="orange", linestyle="--",
               linewidth=1.5, label=f"Sequential  ({seq_mean:.3f} s)")
    ax.set_xlabel("Number of threads")
    ax.set_ylabel("Mean execution time (s)")
    ax.set_title(f"Execution time vs thread count  [{prefix}]")
    ax.legend()
    ax.grid(True, alpha=0.3, axis="y")
    plt.tight_layout()
    plt.savefig(f"{out_dir}/{prefix}_time.png", dpi=150)
    plt.close()

    # Prepend sequential anchor point (1 thread, speedup=1, efficiency=1)
    plot_threads  = [1] + threads.tolist()
    plot_speedup  = [1.0] + grp["speedup"].tolist()
    plot_eff      = [1.0] + grp["efficiency"].tolist()
    ideal_speedup = plot_threads

    # speedup line chart
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(plot_threads, plot_speedup, marker="o",
            color="steelblue", label="Actual speedup")
    ax.plot(plot_threads, ideal_speedup, "--", color="red",
            alpha=0.5, label="Ideal speedup (linear)")
    ax.scatter([1], [1.0], color="orange", zorder=5, label="Sequential (x=1)")
    ax.set_xscale("log", base=2)
    ax.set_xticks(plot_threads)
    ax.get_xaxis().set_major_formatter(plt.ScalarFormatter())
    ax.set_xlabel("Number of threads")
    ax.set_ylabel("Speedup  (T_seq / T_par)")
    ax.set_title(f"Speedup vs thread count  [{prefix}]")
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(f"{out_dir}/{prefix}_speedup.png", dpi=150)
    plt.close()

    # efficiency line chart
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(plot_threads, plot_eff, marker="o", color="steelblue")
    ax.scatter([1], [1.0], color="orange", zorder=5, label="Sequential (x=1)")
    ax.axhline(1.0, color="red", linestyle="--",
               alpha=0.5, label="Ideal efficiency")
    ax.set_xscale("log", base=2)
    ax.set_xticks(plot_threads)
    ax.get_xaxis().set_major_formatter(plt.ScalarFormatter())
    ax.set_ylim(0, max(1.5, max(plot_eff) * 1.15))
    ax.set_xlabel("Number of threads")
    ax.set_ylabel("Efficiency  (speedup / threads)")
    ax.set_title(f"Efficiency vs thread count  [{prefix}]")
    ax.legend()
    ax.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(f"{out_dir}/{prefix}_efficiency.png", dpi=150)
    plt.close()

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True, type=Path)
    parser.add_argument("--out",     required=True, type=Path)
    args = parser.parse_args()

    out_dir = str(args.out)

    for csv_name, prefix in [
        ("same_data.csv", "same_data"),
        ("diff_data.csv", "diff_data"),
    ]:
        csv_path = args.results / csv_name
        if csv_path.exists():
            make_plots(csv_path, out_dir, prefix)
        else:
            print(f"Warning: {csv_path} not found, skipping")

if __name__ == "__main__":
    main()
