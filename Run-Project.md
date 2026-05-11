# Run Project

```bash
# Start the baseline services
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_baseline_only.ps1

# Start the turboquant cache turbo2 services
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_turbo_only.ps1

# Start the API services
powershell -ExecutionPolicy Bypass -File .\S-SOCRATES-BE\scripts\start_api_only.ps1
```

# Test Performance of AI Model with Turboquant Cache Turbo2 Configuration
Run benchmark for testing the performance of the AI model with the turboquant_cache_turbo2 configuration. The benchmark will be run 3 times for each case.

**Baseline with FP16 Cache**

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_baseline `
  --label baseline_cache_fp16 `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_template.csv `
  --runs-per-case 3 `
  --timeout-s 180
```

*reduce parameters for quick test:*

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py --mode ai_baseline --label baseline_cache_fp16 --runs-per-case 3
```

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_baseline `
  --label baseline_cache_fp16_long_context `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_long_context.csv `
  --runs-per-case 3 `
  --timeout-s 300
```

**TurboQuant Cache Turbo2**

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_turbo `
  --label turboquant_cache_turbo2 `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_template.csv `
  --runs-per-case 3 `
  --timeout-s 180
```

*reduce parameters for quick test:*

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py --mode ai_turbo --label turboquant_cache_turbo2 --runs-per-case 3
```

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode ai_turbo `
  --label turboquant_cache_turbo2_long_context `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_long_context.csv `
  --runs-per-case 3 `
  --timeout-s 300
```

**Gemini Reference (Optional)**

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py `
  --base-url http://127.0.0.1:8000 `
  --mode gemini `
  --label gemini_reference `
  --scenario-file .\S-SOCRATES-BE\benchmark\scenarios_template.csv `
  --runs-per-case 3 `
  --timeout-s 120
```

*reduce parameters for quick test:*

```bash
python .\S-SOCRATES-BE\benchmark\run_benchmark.py --mode gemini --label gemini_reference --runs-per-case 3
```