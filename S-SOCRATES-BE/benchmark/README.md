# S-SOCRATES Benchmark Kit

This folder gives you a ready-to-run benchmark framework for TTTN/LVTN:

- scenario CSV input
- raw CSV output
- JSONL log output
- summary CSV output
- report template
- optional chart script

## Files

- `scenarios_template.csv`: test cases
- `scenarios_long_context.csv`: long-context / memory-pressure test cases for TurboQuant
- `run_benchmark.py`: benchmark runner
- `BENCHMARK_LOG_FORMAT.md`: field definitions
- `report_template.md`: thesis report skeleton
- `plot_template.py`: optional chart generator

## 1) Prepare scenario file

Edit:

`S-SOCRATES-BE/benchmark/scenarios_template.csv`

Columns:

- `case_id`
- `category`
- `question`
- `expected_keywords` (semicolon separated)
- `notes`

## 2) Run benchmark (baseline and TurboQuant)

Run from `S-SOCRATES-BE` after backend is up.

### Baseline example

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_baseline `
  --label baseline_cache_fp16 `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_template.csv `
  --runs-per-case 3 `
  --timeout-s 180
```

### TurboQuant example

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_turbo `
  --label turboquant_cache_turbo2 `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_template.csv `
  --runs-per-case 3 `
  --timeout-s 180
```

### Long-context benchmark for TurboQuant evaluation

Use this scenario file when you want to evaluate TurboQuant under the condition it is designed for: longer prompts, more constraints, rare details, and context retention.

Baseline:

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_baseline `
  --label baseline_cache_fp16_long_context `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_long_context.csv `
  --runs-per-case 3 `
  --timeout-s 300
```

TurboQuant:

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_turbo `
  --label turboquant_cache_turbo2_long_context `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_long_context.csv `
  --runs-per-case 3 `
  --timeout-s 300
```

### Gemini reference (optional)

```powershell
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode gemini `
  --label gemini_reference `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_template.csv `
  --runs-per-case 3 `
  --timeout-s 120
```

## 3) Output locations

- Raw rows: `benchmark/results/<label>_<mode>_<timestamp>.csv`
- Summary: `benchmark/results/<label>_<mode>_<timestamp>.summary.csv`
- Structured logs: `benchmark/logs/<label>_<mode>_<timestamp>.jsonl`

## 4) Build thesis tables/charts

1. Open `report_template.md`
2. Copy numbers from summary CSV
3. Optionally generate charts:

```powershell
python .\benchmark\plot_template.py `
  --summary-a .\benchmark\results\baseline_cache_fp16_ai_YYYYMMDD_HHMMSS.summary.csv `
  --summary-b .\benchmark\results\turboquant_cache_turbo2_ai_YYYYMMDD_HHMMSS.summary.csv
```

## 5) Fair comparison checklist

Keep these fixed between runs:

- same model
- same context size
- same scenario CSV
- same backend machine state
- same runs-per-case
- only change cache/quantization setting

For TurboQuant, do not rely only on short-context results. Report short-context and long-context results separately, because TurboQuant is mainly expected to show value when KV-cache/context pressure is higher.
