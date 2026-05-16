"""
Optional chart helper for benchmark summary CSV.

Requires:
    pip install matplotlib
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def load_summary(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def to_float(value: str) -> float:
    try:
        return float(value)
    except Exception:
        return 0.0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-a", required=True, help="Baseline summary CSV path")
    parser.add_argument("--summary-b", required=True, help="TurboQuant summary CSV path")
    parser.add_argument("--out-dir", default=str(Path(__file__).resolve().parent / "charts"))
    args = parser.parse_args()

    try:
        import matplotlib.pyplot as plt
    except Exception as e:
        print("matplotlib is required for plotting:", e)
        return 1

    a_rows = load_summary(Path(args.summary_a))
    b_rows = load_summary(Path(args.summary_b))
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    a_overall = next((r for r in a_rows if r["scope"] == "overall"), None)
    b_overall = next((r for r in b_rows if r["scope"] == "overall"), None)
    if not a_overall or not b_overall:
        print("Missing overall rows in summary files.")
        return 1

    # Chart 1: Overall latency comparison
    labels = ["Mean", "P50", "P95"]
    a_vals = [
        to_float(a_overall["latency_ms_mean"]),
        to_float(a_overall["latency_ms_p50"]),
        to_float(a_overall["latency_ms_p95"]),
    ]
    b_vals = [
        to_float(b_overall["latency_ms_mean"]),
        to_float(b_overall["latency_ms_p50"]),
        to_float(b_overall["latency_ms_p95"]),
    ]

    x = range(len(labels))
    width = 0.35
    plt.figure(figsize=(9, 5))
    plt.bar([i - width / 2 for i in x], a_vals, width=width, label="Baseline")
    plt.bar([i + width / 2 for i in x], b_vals, width=width, label="TurboQuant")
    plt.xticks(list(x), labels)
    plt.ylabel("Latency (ms)")
    plt.title("Overall Latency Comparison")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_dir / "overall_latency_comparison.png", dpi=150)
    plt.close()

    # Chart 2: Success + keyword recall
    labels2 = ["Success rate", "Keyword recall"]
    a_vals2 = [to_float(a_overall["success_rate"]), to_float(a_overall["keyword_recall_mean"])]
    b_vals2 = [to_float(b_overall["success_rate"]), to_float(b_overall["keyword_recall_mean"])]
    x2 = range(len(labels2))

    plt.figure(figsize=(9, 5))
    plt.bar([i - width / 2 for i in x2], a_vals2, width=width, label="Baseline")
    plt.bar([i + width / 2 for i in x2], b_vals2, width=width, label="TurboQuant")
    plt.xticks(list(x2), labels2)
    plt.ylim(0, 1.0)
    plt.title("Quality/Robustness Comparison")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_dir / "quality_comparison.png", dpi=150)
    plt.close()

    print(f"Charts generated in: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

