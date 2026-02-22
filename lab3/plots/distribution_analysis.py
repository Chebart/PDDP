import os
import sys

import psycopg2
import matplotlib
import matplotlib.pyplot as plt

matplotlib.use("Agg")
GP_HOST = os.environ.get("GP_HOST", "localhost")
GP_PORT = int(os.environ.get("GP_PORT", "5432"))
GP_DB   = os.environ.get("GP_DATABASE", "toystore")
GP_USER = os.environ.get("GP_USER", "gpadmin")

TABLES = [
    "products",
    "website_sessions",
    "website_pageviews",
    "orders",
    "order_items",
    "order_item_refunds",
]

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))


def query_distribution(conn):
    parts = [
        f"SELECT '{t}' AS tbl, gp_segment_id, COUNT(*) AS rows FROM {t} GROUP BY gp_segment_id"
        for t in TABLES
    ]
    with conn.cursor() as cur:
        cur.execute(" UNION ALL ".join(parts))
        rows = cur.fetchall()
    result = {}
    for tbl, seg_id, count in rows:
        result.setdefault(tbl, {})[seg_id] = count
    return result


def plot_distribution(dist, label, filename):
    cols = 3
    rows_count = (len(TABLES) + cols - 1) // cols
    fig, axes = plt.subplots(rows_count, cols, figsize=(14, 4 * rows_count))
    fig.suptitle(f"Segment distribution — {label}", fontsize=13, fontweight="bold")
    axes = axes.flatten()

    colors = ["#4C72B0", "#DD8452", "#55A868", "#C44E52", "#8172B2", "#937860"]

    for i, tbl in enumerate(TABLES):
        ax = axes[i]
        seg_data = dist.get(tbl, {})
        segs = sorted(seg_data.keys())
        counts = [seg_data[s] for s in segs]
        total = sum(counts) or 1
        pcts = [c * 100.0 / total for c in counts]

        bars = ax.bar(
            [f"seg {s}" for s in segs],
            pcts,
            color=colors[: len(segs)],
            edgecolor="white",
        )
        ax.set_title(tbl, fontsize=10)
        ax.set_ylabel("% of rows")
        ax.set_ylim(0, max(pcts) * 1.25 + 5)
        ax.axhline(100.0 / len(segs), color="gray", linewidth=0.8, linestyle="--")

        for bar, pct in zip(bars, pcts):
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height() + 0.5,
                f"{pct:.1f}%",
                ha="center",
                va="bottom",
                fontsize=9,
            )

    for j in range(i + 1, len(axes)):
        axes[j].set_visible(False)

    plt.tight_layout()
    out = os.path.join(OUTPUT_DIR, filename)
    plt.savefig(out, dpi=130)
    plt.close()
    print(f"Saved: {out}")


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "v1"
    label_map = {
        "v1": "before redistribution (v1)",
        "v2": "after redistribution (v2)",
    }
    label = label_map.get(phase, phase)
    filename = f"distribution_{phase}.png"

    print(f"Connecting to Greenplum at {GP_HOST}:{GP_PORT}/{GP_DB} ...")
    conn = psycopg2.connect(host=GP_HOST, port=GP_PORT, dbname=GP_DB, user=GP_USER)
    try:
        dist = query_distribution(conn)
        plot_distribution(dist, label, filename)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
