import csv
import re
from datetime import datetime
from pathlib import Path


RUN_START_RE = re.compile(r"^===== START\s+(.+?)\s+=====$")
MODEL_RE = re.compile(r"loading model '(.+?)'")
N_CTX_RE = re.compile(r"llama_context:\s+n_ctx\s*=\s*(\d+)")
KV_BUFFER_RE = re.compile(r"llama_kv_cache:\s+(.+?)\s+KV buffer size\s*=\s*([\d.]+)\s+MiB")
KV_SIZE_RE = re.compile(
    r"llama_kv_cache:\s+size\s*=\s*([\d.]+)\s+MiB.*?K\s+\(([^)]+)\):\s*([\d.]+)\s+MiB,\s*V\s+\(([^)]+)\):\s*([\d.]+)\s+MiB"
)
TASK_START_RE = re.compile(r"slot launch_slot_:\s+id\s+(\d+)\s+\|\s+task\s+(-?\d+)\s+\|\s+processing task")
TASK_SLOT_SELECT_RE = re.compile(r"slot get_availabl:\s+id\s+(\d+)\s+\|\s+task\s+(-?\d+)\s+\|\s+selected slot by (.+)")
TASK_SIM_RE = re.compile(r"sim_best\s*=\s*([0-9.]+)")
TASK_RESTORE_RE = re.compile(r"slot update_slots:\s+id\s+(\d+)\s+\|\s+task\s+(-?\d+)\s+\|\s+restored context checkpoint")
TASK_PROMPT_RE = re.compile(r"prompt eval time\s*=\s*([0-9.]+)\s*ms\s*/\s*(\d+)\s*tokens")
TASK_EVAL_RE = re.compile(r"eval time\s*=\s*([0-9.]+)\s*ms\s*/\s*(\d+)\s*tokens")
TASK_TOTAL_RE = re.compile(r"total time\s*=\s*([0-9.]+)\s*ms\s*/\s*(\d+)\s*tokens")
TASK_DONE_RE = re.compile(r"done request:\s+POST\s+/v1/chat/completions")


def normalize_selector(selector: str) -> tuple[str, str] | None:
    text = selector.strip()
    if not text:
        return None

    cleaned = re.sub(r"^=+\s*START\s*", "", text, flags=re.IGNORECASE).strip()
    cleaned = re.sub(r"\s*=+$", "", cleaned).strip()
    cleaned = re.sub(r"^START\s*", "", cleaned, flags=re.IGNORECASE).strip()

    for fmt in ("%Y-%m-%d %H:%M:%S", "%H:%M:%S"):
        try:
            dt = datetime.strptime(cleaned, fmt)
            if fmt == "%Y-%m-%d %H:%M:%S":
                return ("full", dt.strftime("%Y-%m-%d %H:%M:%S"))
            return ("time", dt.strftime("%H:%M:%S"))
        except ValueError:
            continue
    return None


def parse_turn_metrics(log_path: Path) -> list[dict]:
    rows: list[dict] = []
    current_run = None
    active_task = None
    pending_timing_task = None

    def finalize_active():
        nonlocal active_task
        if active_task is None:
            return
        rows.append(active_task)
        active_task = None

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        for raw_line in f:
            line = raw_line.strip()

            run_match = RUN_START_RE.match(line)
            if run_match:
                finalize_active()
                current_run = run_match.group(1)
                pending_timing_task = None
                continue

            start_match = TASK_START_RE.search(line)
            if start_match:
                finalize_active()
                slot_id = int(start_match.group(1))
                task_id = int(start_match.group(2))
                if task_id < 0:
                    continue
                active_task = {
                    "run_start": current_run,
                    "log_file": str(log_path),
                    "slot_id": slot_id,
                    "task_id": task_id,
                    "slot_selection": "",
                    "sim_best": "",
                    "restored_checkpoint_count": 0,
                    "prompt_eval_ms": "",
                    "prompt_eval_tokens": "",
                    "eval_ms": "",
                    "eval_tokens": "",
                    "total_ms": "",
                    "total_tokens": "",
                    "request_done": 0,
                }
                continue

            if active_task is None:
                continue

            select_match = TASK_SLOT_SELECT_RE.search(line)
            if select_match and int(select_match.group(2)) == active_task["task_id"]:
                selection = select_match.group(3).strip()
                active_task["slot_selection"] = selection
                sim_match = TASK_SIM_RE.search(line)
                if sim_match:
                    active_task["sim_best"] = sim_match.group(1)
                continue

            restore_match = TASK_RESTORE_RE.search(line)
            if restore_match and int(restore_match.group(2)) == active_task["task_id"]:
                active_task["restored_checkpoint_count"] += 1
                continue

            if f"slot print_timing: id" in line and f"task {active_task['task_id']}" in line:
                pending_timing_task = active_task["task_id"]
                continue

            if pending_timing_task == active_task["task_id"]:
                prompt_match = TASK_PROMPT_RE.search(line)
                if prompt_match:
                    active_task["prompt_eval_ms"] = float(prompt_match.group(1))
                    active_task["prompt_eval_tokens"] = int(prompt_match.group(2))
                    continue

                eval_match = TASK_EVAL_RE.search(line)
                if eval_match:
                    active_task["eval_ms"] = float(eval_match.group(1))
                    active_task["eval_tokens"] = int(eval_match.group(2))
                    continue

                total_match = TASK_TOTAL_RE.search(line)
                if total_match:
                    active_task["total_ms"] = float(total_match.group(1))
                    active_task["total_tokens"] = int(total_match.group(2))
                    pending_timing_task = None
                    continue

            if TASK_DONE_RE.search(line):
                active_task["request_done"] = 1
                finalize_active()
                pending_timing_task = None

    finalize_active()
    return rows


def parse_run_metrics(log_path: Path) -> list[dict]:
    rows: list[dict] = []
    current = {}

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        for raw_line in f:
            line = raw_line.strip()

            match_start = RUN_START_RE.match(line)
            if match_start:
                if current:
                    rows.append(current)
                current = {
                    "run_start": match_start.group(1),
                    "log_file": str(log_path),
                }
                continue

            if not current:
                continue

            if "loading model '" in line:
                model_match = MODEL_RE.search(line)
                if model_match:
                    current["model_path"] = model_match.group(1)
                    current["model_name"] = Path(model_match.group(1)).name

            nctx_match = N_CTX_RE.search(line)
            if nctx_match:
                current["n_ctx"] = int(nctx_match.group(1))

            kv_buffer_match = KV_BUFFER_RE.search(line)
            if kv_buffer_match:
                current["kv_device"] = kv_buffer_match.group(1).strip()
                current["kv_buffer_mib"] = float(kv_buffer_match.group(2))

            kv_size_match = KV_SIZE_RE.search(line)
            if kv_size_match:
                current["kv_total_mib"] = float(kv_size_match.group(1))
                current["k_cache_type"] = kv_size_match.group(2)
                current["k_mib"] = float(kv_size_match.group(3))
                current["v_cache_type"] = kv_size_match.group(4)
                current["v_mib"] = float(kv_size_match.group(5))

    if current:
        rows.append(current)

    return rows


def filter_rows_by_start(rows: list[dict], selector: str) -> list[dict]:
    normalized = normalize_selector(selector)
    if not normalized:
        return []

    mode, key = normalized
    if mode == "full":
        return [r for r in rows if r.get("run_start") == key]
    return [r for r in rows if str(r.get("run_start", "")).endswith(key)]


def write_turn_csv(rows: list[dict], out_path: Path) -> None:
    fieldnames = [
        "run_start",
        "task_id",
        "slot_id",
        "slot_selection",
        "sim_best",
        "restored_checkpoint_count",
        "prompt_eval_ms",
        "prompt_eval_tokens",
        "eval_ms",
        "eval_tokens",
        "total_ms",
        "total_tokens",
        "request_done",
        "log_file",
    ]
    with out_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_run_csv(rows: list[dict], out_path: Path) -> None:
    fieldnames = [
        "run_start",
        "log_file",
        "model_name",
        "model_path",
        "n_ctx",
        "kv_device",
        "kv_buffer_mib",
        "kv_total_mib",
        "k_cache_type",
        "k_mib",
        "v_cache_type",
        "v_mib",
    ]
    with out_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> None:
    print("=== KV-Cache Metrics Exporter (Run + Per-Turn) ===")
    print("Example log: S-SOCRATES-BE/logs/turboquant.stderr.log")
    input_path = input("Nhap duong dan file log can trich xuat: ").strip().strip('"')
    if not input_path:
        print("Khong co duong dan. Da huy.")
        return

    log_path = Path(input_path).expanduser().resolve()
    if not log_path.exists() or not log_path.is_file():
        print(f"Khong tim thay file: {log_path}")
        return

    turn_rows = parse_turn_metrics(log_path)
    run_rows = parse_run_metrics(log_path)
    if not turn_rows and not run_rows:
        print("Khong tim thay du lieu per-turn trong file log.")
        return

    run_starts = sorted({r.get("run_start", "") for r in (turn_rows + run_rows) if r.get("run_start")})
    if run_starts:
        print("\nCac moc run tim thay trong log:")
        for i, run_start in enumerate(run_starts, start=1):
            print(f"{i}. {run_start}")

    print("\nNhap moc thoi gian can lay.")
    selector = input("Moc thoi gian: ").strip()

    selected_turn_rows = turn_rows
    selected_run_rows = run_rows
    if selector:
        selected_turn_rows = filter_rows_by_start(turn_rows, selector)
        selected_run_rows = filter_rows_by_start(run_rows, selector)
        if not selected_turn_rows and not selected_run_rows:
            print("Khong tim thay run phu hop voi moc thoi gian da nhap.")
            return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_out_path = log_path.parent / f"kv_cache_metrics_{timestamp}.csv"
    turn_out_path = log_path.parent / f"kv_cache_turn_metrics_{timestamp}.csv"

    write_run_csv(selected_run_rows, run_out_path)
    write_turn_csv(selected_turn_rows, turn_out_path)

    print(f"Da trich xuat run-level: {len(selected_run_rows)} dong.")
    print(f"File CSV run-level: {run_out_path}")
    print(f"Da trich xuat per-turn: {len(selected_turn_rows)} dong.")
    print(f"File CSV per-turn: {turn_out_path}")


if __name__ == "__main__":
    main()
