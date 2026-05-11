# Benchmark Log Format (S-SOCRATES)

This benchmark framework writes:

- `benchmark/results/<label>_<mode>_<timestamp>.csv` (raw rows)
- `benchmark/results/<label>_<mode>_<timestamp>.summary.csv` (aggregates)
- `benchmark/logs/<label>_<mode>_<timestamp>.jsonl` (structured log)

## Raw CSV / JSONL fields

- `run_index`: global row index
- `started_at_utc`: request start timestamp
- `label`: experiment label, e.g. `turboquant_on`
- `model_mode`: `ai` (local) or `gemini`
- `case_id`: scenario id from CSV
- `category`: scenario category
- `repeat`: nth run for same case
- `question`: input question
- `question_chars`: input length
- `response_text`: model output text
- `response_chars`: output length
- `latency_ms`: end-to-end latency for `/operator-decision`
- `http_status`: HTTP response code
- `success`: `1` if no backend error field, else `0`
- `error`: error message if any
- `expected_keywords`: semicolon keyword list
- `keyword_total`: number of expected keywords
- `keyword_hit`: how many expected keywords were found in response
- `keyword_recall`: `keyword_hit / keyword_total`
- `notes`: free notes from scenario file

## Summary CSV fields

- `scope`: `overall`, `category:<name>`, `case:<id>`
- `samples`
- `success_rate`
- `latency_ms_mean`
- `latency_ms_p50`
- `latency_ms_p95`
- `latency_ms_max`
- `keyword_recall_mean`

## Recommended experiment labels

- `baseline_cache_fp16` (no TurboQuant)
- `turboquant_cache_turbo2`

Keep all other settings fixed:

- same model file
- same context size
- same scenario CSV
- same runs-per-case
