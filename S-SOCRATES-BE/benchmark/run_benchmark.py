"""
S-SOCRATES benchmark runner

Outputs:
1) raw per-request CSV
2) structured JSONL log
3) summary CSV (overall + by category + by case)
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


@dataclass
class Scenario:
    case_id: str
    category: str
    question: str
    expected_keywords: list[str]
    notes: str


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_scenarios(path: Path) -> list[Scenario]:
    items: list[Scenario] = []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"case_id", "category", "question", "expected_keywords", "notes"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"Missing CSV headers: {sorted(missing)}")

        for row in reader:
            question = (row.get("question") or "").strip()
            if not question:
                continue
            keywords = [
                token.strip().lower()
                for token in (row.get("expected_keywords") or "").split(";")
                if token.strip()
            ]
            items.append(
                Scenario(
                    case_id=(row.get("case_id") or "").strip() or f"case_{len(items)+1}",
                    category=(row.get("category") or "").strip() or "general",
                    question=question,
                    expected_keywords=keywords,
                    notes=(row.get("notes") or "").strip(),
                )
            )
    if not items:
        raise ValueError("Scenario CSV is empty.")
    return items


def _json_post(url: str, payload: dict[str, Any], timeout_s: float) -> tuple[int, dict[str, Any] | None, str | None]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(
        url=url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=timeout_s) as resp:
            text = resp.read().decode("utf-8", errors="replace")
            try:
                return resp.status, json.loads(text), None
            except json.JSONDecodeError:
                return resp.status, None, f"Non-JSON response: {text[:400]}"
    except HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        return e.code, None, f"HTTPError {e.code}: {raw[:400]}"
    except URLError as e:
        return 0, None, f"URLError: {e}"
    except Exception as e:  # pragma: no cover - defensive path
        return 0, None, f"Unhandled request error: {e}"


def contains_word(text: str, word: str) -> bool:
    return word.lower() in text.lower()


def percentile(values: list[float], p: float) -> float:
    if not values:
        return math.nan
    if len(values) == 1:
        return values[0]
    rank = (len(values) - 1) * p
    low = int(math.floor(rank))
    high = int(math.ceil(rank))
    if low == high:
        return values[low]
    frac = rank - low
    return values[low] * (1 - frac) + values[high] * frac


def csv_single_line(value: str) -> str:
    """Keep generated text readable without letting newlines split CSV rows."""
    return (
        str(value or "")
        .replace("\r\n", "\\n")
        .replace("\r", "\\n")
        .replace("\n", "\\n")
    )


def ensure_dirs() -> tuple[Path, Path]:
    root = Path(__file__).resolve().parent
    results = root / "results"
    logs = root / "logs"
    results.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    return results, logs


def write_summary(summary_path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    with summary_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run S-SOCRATES benchmark and export CSV/JSONL.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000", help="Backend base URL")
    parser.add_argument(
        "--mode",
        default="ai",
        choices=["ai", "ai_turbo", "ai_baseline", "baseline", "gemini"],
        help="Model mode for /operator-decision",
    )
    parser.add_argument(
        "--label",
        default="experiment",
        help="Experiment label, e.g. turboquant_on / turboquant_off",
    )
    parser.add_argument(
        "--scenario-file",
        default=str(Path(__file__).resolve().parent / "scenarios_template.csv"),
        help="Scenario CSV path",
    )
    parser.add_argument("--runs-per-case", type=int, default=3, help="How many repeated runs per case")
    parser.add_argument("--timeout-s", type=float, default=180.0, help="Request timeout in seconds")
    parser.add_argument("--sleep-ms", type=int, default=200, help="Sleep between requests")
    args = parser.parse_args()

    scenario_path = Path(args.scenario_file).resolve()
    scenarios = read_scenarios(scenario_path)
    results_dir, logs_dir = ensure_dirs()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    stem = f"{args.label}_{args.mode}_{timestamp}"
    raw_csv_path = results_dir / f"{stem}.csv"
    summary_csv_path = results_dir / f"{stem}.summary.csv"
    jsonl_log_path = logs_dir / f"{stem}.jsonl"

    raw_rows: list[dict[str, Any]] = []

    with jsonl_log_path.open("w", encoding="utf-8") as jsonl:
        run_idx = 0
        for case in scenarios:
            for repeat in range(1, args.runs_per_case + 1):
                run_idx += 1
                started_iso = utc_now_iso()
                t0 = time.perf_counter()
                status_code, payload, req_error = _json_post(
                    url=f"{args.base_url.rstrip('/')}/operator-decision",
                    payload={"mode": args.mode, "transcript": case.question},
                    timeout_s=args.timeout_s,
                )
                latency_ms = (time.perf_counter() - t0) * 1000.0

                text = ""
                error = req_error
                success = 0
                if payload is not None:
                    text = str(payload.get("text") or "")
                    if payload.get("error"):
                        error = str(payload["error"])
                    else:
                        success = 1
                if status_code >= 400:
                    success = 0
                    if not error:
                        error = f"HTTP status {status_code}"

                keyword_hits = 0
                if text and case.expected_keywords:
                    keyword_hits = sum(1 for kw in case.expected_keywords if contains_word(text, kw))

                row = {
                    "run_index": run_idx,
                    "started_at_utc": started_iso,
                    "label": args.label,
                    "model_mode": args.mode,
                    "case_id": case.case_id,
                    "category": case.category,
                    "repeat": repeat,
                    "question": case.question,
                    "question_chars": len(case.question),
                    "response_text": csv_single_line(text),
                    "response_chars": len(text),
                    "latency_ms": round(latency_ms, 2),
                    "http_status": status_code,
                    "success": success,
                    "error": error or "",
                    "expected_keywords": ";".join(case.expected_keywords),
                    "keyword_total": len(case.expected_keywords),
                    "keyword_hit": keyword_hits,
                    "keyword_recall": round((keyword_hits / len(case.expected_keywords)), 4)
                    if case.expected_keywords
                    else "",
                    "notes": case.notes,
                }
                raw_rows.append(row)
                jsonl.write(json.dumps(row, ensure_ascii=False) + "\n")
                jsonl.flush()

                if args.sleep_ms > 0:
                    time.sleep(args.sleep_ms / 1000.0)

    with raw_csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(raw_rows[0].keys()))
        writer.writeheader()
        writer.writerows(raw_rows)

    # Summary rows
    summary_rows: list[dict[str, Any]] = []

    def build_summary(name: str, scope_rows: list[dict[str, Any]]) -> dict[str, Any]:
        latencies = [float(r["latency_ms"]) for r in scope_rows if r["success"] == 1]
        success_rate = sum(int(r["success"]) for r in scope_rows) / len(scope_rows) if scope_rows else 0.0
        keyword_scores = [float(r["keyword_recall"]) for r in scope_rows if str(r["keyword_recall"]).strip()]
        return {
            "scope": name,
            "samples": len(scope_rows),
            "success_rate": round(success_rate, 4),
            "latency_ms_mean": round(statistics.mean(latencies), 2) if latencies else "",
            "latency_ms_p50": round(percentile(sorted(latencies), 0.50), 2) if latencies else "",
            "latency_ms_p95": round(percentile(sorted(latencies), 0.95), 2) if latencies else "",
            "latency_ms_max": round(max(latencies), 2) if latencies else "",
            "keyword_recall_mean": round(statistics.mean(keyword_scores), 4) if keyword_scores else "",
        }

    summary_rows.append(build_summary("overall", raw_rows))

    categories = sorted(set(r["category"] for r in raw_rows))
    for category in categories:
        scope = [r for r in raw_rows if r["category"] == category]
        summary_rows.append(build_summary(f"category:{category}", scope))

    cases = sorted(set(r["case_id"] for r in raw_rows))
    for case_id in cases:
        scope = [r for r in raw_rows if r["case_id"] == case_id]
        summary_rows.append(build_summary(f"case:{case_id}", scope))

    write_summary(summary_csv_path, summary_rows)

    print("Benchmark completed.")
    print(f"Raw CSV: {raw_csv_path}")
    print(f"Summary CSV: {summary_csv_path}")
    print(f"JSONL log: {jsonl_log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
